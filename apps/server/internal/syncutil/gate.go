// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// Package syncutil provides cancellable admission without holding state locks.
package syncutil

import (
	"context"
	"sync"
)

// Gate is a zero-value-ready, cancellable mutex. It must not be copied after use.
type Gate struct {
	once  sync.Once
	token chan struct{}
}

func (g *Gate) Lock(ctx context.Context) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	g.once.Do(func() { g.token = make(chan struct{}, 1) })
	select {
	case g.token <- struct{}{}:
		if err := ctx.Err(); err != nil {
			g.Unlock()
			return err
		}
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

func (g *Gate) Unlock() { <-g.token }

// KeyedGate retains only currently held or awaited keys. Admission limits at
// its callers bound the number of concurrent entries; idle identities cost no memory.
type KeyedGate struct {
	mu      sync.Mutex
	entries map[string]*gateEntry
}

type gateEntry struct {
	gate Gate
	refs int
}

func (g *KeyedGate) Lock(ctx context.Context, key string) (func(), error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	g.mu.Lock()
	if g.entries == nil {
		g.entries = make(map[string]*gateEntry)
	}
	entry := g.entries[key]
	if entry == nil {
		entry = &gateEntry{}
		g.entries[key] = entry
	}
	entry.refs++
	g.mu.Unlock()
	drop := func() {
		g.mu.Lock()
		defer g.mu.Unlock()
		entry.refs--
		if entry.refs == 0 {
			delete(g.entries, key)
		}
	}
	if err := entry.gate.Lock(ctx); err != nil {
		drop()
		return nil, err
	}
	return func() { entry.gate.Unlock(); drop() }, nil
}
