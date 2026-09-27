// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package cluster

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"math"
	"sort"
	"sync"
	"time"

	"hexproof/server/internal/protocol"
)

var (
	ErrUnavailable  = errors.New("cluster unavailable")
	ErrFull         = errors.New("cluster capacity unavailable")
	ErrInvalid      = errors.New("invalid cluster request or ticket")
	ErrFenced       = errors.New("cluster node generation replaced")
	ErrRegistration = errors.New("cluster registration required")
)

const NodeLifetime = 10 * time.Second
const TicketLifetime = 30 * time.Second

type Report struct {
	Version        string                                `json:"version"`
	Rooms          []protocol.RoomListEntry              `json:"rooms"`
	Events         []protocol.TournamentListEntry        `json:"events"`
	Resources      map[string][]protocol.AccountResource `json:"resources"`
	RoomCount      int                                   `json:"roomCount"`
	MaxRooms       int                                   `json:"maxRooms"`
	EventCount     int                                   `json:"eventCount"`
	MaxEvents      int                                   `json:"maxEvents"`
	Connections    int64                                 `json:"connections"`
	MaxConnections int64                                 `json:"maxConnections"`
	ForgeDemand    int                                   `json:"forgeDemand"`
	MaxForge       int                                   `json:"maxForge"`
	Forge          bool                                  `json:"forge"`
	ForgeAI        bool                                  `json:"forgeAI"`
	PlayerHosting  bool                                  `json:"playerHosting"`
	MemoryMB       int64                                 `json:"memoryMB"`
	Load           float64                               `json:"load"`
}

type Demand struct {
	Rooms         int  `json:"rooms"`
	Events        int  `json:"events"`
	Forge         int  `json:"forge"`
	ForgeAI       bool `json:"forgeAI"`
	PlayerHosting bool `json:"playerHosting"`
}

type Ticket struct {
	Token       string    `json:"token"`
	NodeID      string    `json:"nodeId"`
	Origin      string    `json:"origin"`
	URL         string    `json:"url"`
	AccountID   string    `json:"accountId"`
	CommandType string    `json:"commandType"`
	Digest      string    `json:"digest"`
	ExpiresAt   time.Time `json:"expiresAt"`
	Generation  string    `json:"generation"`
	Demand      Demand    `json:"demand"`
	Taken       bool      `json:"taken"`
}

type Request struct {
	Operation      string         `json:"operation"`
	ReportSequence uint64         `json:"reportSequence,omitempty"`
	NodeID         string         `json:"nodeId"`
	Generation     string         `json:"generation"`
	Report         *Report        `json:"report,omitempty"`
	Completed      []string       `json:"completed,omitempty"`
	Target         string         `json:"target,omitempty"`
	AccountID      string         `json:"accountId,omitempty"`
	CommandType    string         `json:"commandType,omitempty"`
	Digest         string         `json:"digest,omitempty"`
	Token          string         `json:"token,omitempty"`
	Demand         Demand         `json:"demand"`
	Latency        map[string]int `json:"latency,omitempty"`
}

type Result struct {
	Generation    string                         `json:"generation,omitempty"`
	Ticket        *Ticket                        `json:"ticket,omitempty"`
	Rooms         []protocol.RoomListEntry       `json:"rooms"`
	Events        []protocol.TournamentListEntry `json:"events"`
	Resources     []protocol.AccountResource     `json:"resources"`
	Forge         bool                           `json:"forge,omitempty"`
	ForgeAI       bool                           `json:"forgeAI,omitempty"`
	PlayerHosting bool                           `json:"playerHosting,omitempty"`
}

type Service interface {
	Do(context.Context, Request) (Result, error)
}
type nodeState struct {
	reportSequence uint64
	generation     string
	seen           time.Time
	report         Report
}
type Coordinator struct {
	mu      sync.Mutex
	nodes   map[string]Node
	states  map[string]nodeState
	tickets map[string]Ticket
	now     func() time.Time
}

func New(c Config) (*Coordinator, error) {
	if err := c.Validate(); err != nil {
		return nil, err
	}
	x := &Coordinator{nodes: map[string]Node{}, states: map[string]nodeState{}, tickets: map[string]Ticket{}, now: time.Now}
	for _, n := range c.Nodes {
		x.nodes[n.ID] = n
	}
	return x, nil
}

func randomToken() string { var b [32]byte; rand.Read(b[:]); return hex.EncodeToString(b[:]) }

func (c *Coordinator) Do(ctx context.Context, q Request) (Result, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if ctx.Err() != nil {
		return Result{}, ErrUnavailable
	}
	var out Result
	now := c.now().UTC()
	for token, t := range c.tickets {
		if !now.Before(t.ExpiresAt) {
			delete(c.tickets, token)
		}
	}
	if _, ok := c.nodes[q.NodeID]; !ok {
		return out, ErrInvalid
	}
	if q.Operation == "register" {
		generation := randomToken()
		c.states[q.NodeID] = nodeState{generation: generation}
		return Result{Generation: generation}, nil
	}
	s, ok := c.states[q.NodeID]
	if !ok {
		return out, ErrRegistration
	}
	if s.generation != q.Generation {
		return out, ErrFenced
	}
	switch q.Operation {
	case "report":
		if q.ReportSequence == 0 || q.Report == nil || !validReport(*q.Report) || len(q.Completed) > 2048 {
			return out, ErrInvalid
		}
		// Delayed HTTP retries cannot replace a newer capacity snapshot or
		// refresh the health lease. Sequence ownership resets on registration.
		if q.ReportSequence <= s.reportSequence {
			out.Forge, out.ForgeAI, out.PlayerHosting = c.capabilities(s.report.Version, now)
			return out, nil
		}
		// A report is a full snapshot. Decode into fresh storage so omitted
		// fields and removed map keys cannot survive from the previous report.
		var nextReport Report
		raw, err := json.Marshal(q.Report)
		if err != nil || json.Unmarshal(raw, &nextReport) != nil {
			return out, ErrInvalid
		}
		s.report = nextReport
		s.reportSequence = q.ReportSequence
		s.seen = now
		c.states[q.NodeID] = s
		for _, token := range q.Completed {
			if t, ok := c.tickets[token]; ok && t.NodeID == q.NodeID && t.Generation == q.Generation && t.Taken {
				delete(c.tickets, token)
			}
		}
		out.Forge, out.ForgeAI, out.PlayerHosting = c.capabilities(s.report.Version, now)
	case "allocate":
		if len(c.tickets) >= 2048 || q.Digest == "" || len(q.Digest) != 64 || len(q.CommandType) > 64 || len(q.AccountID) > 64 || !validDemand(q.Demand) {
			return out, ErrInvalid
		}
		id := c.selectNode(q, s.report.Version, now)
		if id == "" {
			return out, ErrFull
		}
		t := Ticket{Token: randomToken(), NodeID: id, Origin: q.NodeID, URL: c.nodes[id].URL, AccountID: q.AccountID, CommandType: q.CommandType, Digest: q.Digest, ExpiresAt: now.Add(TicketLifetime), Generation: c.states[id].generation, Demand: q.Demand}
		c.tickets[t.Token] = t
		out.Ticket = &t
	case "take":
		t, ok := c.tickets[q.Token]
		if !ok || t.Taken || t.NodeID != q.NodeID || t.Generation != q.Generation || t.AccountID != q.AccountID {
			return out, ErrInvalid
		}
		t.Taken = true
		c.tickets[q.Token] = t
		out.Ticket = &t
	case "view":
		out = c.view(s.report.Version, q.AccountID, now)
	default:
		return out, ErrInvalid
	}
	return out, nil
}

func validDemand(d Demand) bool {
	return d.Rooms >= 0 && d.Rooms <= 1 && d.Events >= 0 && d.Events <= 1 && d.Forge >= 0 && d.Forge <= 128
}

func validReport(r Report) bool {
	if r.Version == "" || len(r.Version) > 64 || len(r.Rooms) > 2048 || len(r.Events) > 256 || len(r.Resources) > 16384 || r.RoomCount < 0 || r.EventCount < 0 || r.ForgeDemand < 0 || r.MaxRooms < 1 || r.MaxEvents < 1 || r.MaxConnections < 1 || r.MaxForge < 0 || r.Connections < 0 || r.Load < 0 || math.IsNaN(r.Load) || math.IsInf(r.Load, 0) {
		return false
	}
	for aid, resources := range r.Resources {
		if len(aid) > 64 || len(resources) > 256 {
			return false
		}
	}
	return true
}

func (c *Coordinator) selectNode(q Request, version string, now time.Time) string {
	best, score := "", math.Inf(1)
	for id, n := range c.nodes {
		s, ok := c.states[id]
		if !ok || now.Sub(s.seen) >= NodeLifetime || s.report.Version != version || (q.Target != "" && q.Target != id) {
			continue
		}
		r := s.report
		rooms, events, forge := r.RoomCount, r.EventCount, r.ForgeDemand
		connections := r.Connections
		for _, t := range c.tickets {
			if t.NodeID == id && t.Generation == s.generation {
				rooms += t.Demand.Rooms
				events += t.Demand.Events
				forge += t.Demand.Forge
				if t.Origin != id {
					connections++
				}
			}
		}
		d := q.Demand
		if (id != q.NodeID && connections >= r.MaxConnections) || (d.Rooms > 0 && rooms+d.Rooms > r.MaxRooms) || (d.Events > 0 && events+d.Events > r.MaxEvents) || (d.Forge > 0 && (!r.Forge || forge+d.Forge > r.MaxForge || (r.MemoryMB > 0 && r.MemoryMB < int64(d.Forge)*384))) || (d.ForgeAI && !r.ForgeAI) || (d.PlayerHosting && !r.PlayerHosting) {
			continue
		}
		load := float64(rooms+events*2+forge*4+1)/float64(n.Weight) + r.Load*2
		// An unchecked endpoint is not a zero-latency endpoint. A failed
		// client probe is a bounded penalty, not authority to mark a node down.
		latency := 250
		if measured, ok := q.Latency[n.URL]; ok {
			latency = max(0, min(measured, 2000))
			if measured < 0 {
				latency = 2000
			}
		}
		load += float64(latency) / 250
		if load < score || (load == score && id < best) {
			best, score = id, load
		}
	}
	return best
}

func (c *Coordinator) view(version, accountID string, now time.Time) Result {
	out := Result{Rooms: []protocol.RoomListEntry{}, Events: []protocol.TournamentListEntry{}, Resources: []protocol.AccountResource{}}
	for id, s := range c.states {
		if now.Sub(s.seen) >= NodeLifetime || s.report.Version != version {
			continue
		}
		out.Forge = out.Forge || s.report.Forge
		out.ForgeAI = out.ForgeAI || s.report.ForgeAI
		out.PlayerHosting = out.PlayerHosting || s.report.PlayerHosting
		for _, r := range s.report.Rooms {
			r.RoomID = GlobalCode(id, r.RoomID)
			r.NodeName = c.nodes[id].Name
			out.Rooms = append(out.Rooms, r)
		}
		for _, e := range s.report.Events {
			e.TournamentID = GlobalCode(id, e.TournamentID)
			e.NodeName = c.nodes[id].Name
			out.Events = append(out.Events, e)
		}
		if accountID != "" {
			for _, r := range s.report.Resources[accountID] {
				r.ID = GlobalCode(id, r.ID)
				r.NodeName = c.nodes[id].Name
				out.Resources = append(out.Resources, r)
			}
		}
	}
	sort.Slice(out.Rooms, func(i, j int) bool { return out.Rooms[i].RoomID < out.Rooms[j].RoomID })
	sort.Slice(out.Events, func(i, j int) bool { return out.Events[i].TournamentID < out.Events[j].TournamentID })
	sort.Slice(out.Resources, func(i, j int) bool {
		return out.Resources[i].Kind+out.Resources[i].ID < out.Resources[j].Kind+out.Resources[j].ID
	})
	return out
}

func (c *Coordinator) capabilities(version string, now time.Time) (forge, ai, hosting bool) {
	for _, s := range c.states {
		if now.Sub(s.seen) < NodeLifetime && s.report.Version == version {
			forge, ai, hosting = forge || s.report.Forge, ai || s.report.ForgeAI, hosting || s.report.PlayerHosting
		}
	}
	return
}
