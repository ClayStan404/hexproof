// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package room

import (
	"strings"

	"hexproof/server/internal/protocol"
)

type cardMovePlan struct {
	actorSeat  int
	sourceSeat int
	targetSeat int
}

type cardBatchMovePlan struct {
	actorSeat  int
	sourceSeat int
	targetSeat int
	cardIDs    []string
}

func (r *Room) moveActor(connID string) (int, error) {
	if err := r.requireActiveGame(); err != nil {
		return 0, err
	}
	actorSeat, err := r.playerSeat(connID, false)
	if err != nil {
		return 0, err
	}
	return actorSeat, nil
}

func (r *Room) moveSource(actorSeat int, fromZone string, fromSeat *int) (int, error) {
	sourceSeat := actorSeat
	if fromSeat != nil {
		if !publicPlayerZone(fromZone) {
			return 0, newError(protocol.ErrInvalidMove)
		}
		sourceSeat = *fromSeat
	}
	if sourceSeat < 0 || sourceSeat >= len(r.Game.Seats) {
		return 0, newError(protocol.ErrInvalidTarget)
	}
	return sourceSeat, nil
}

func requirePublicSourceApproval(actorSeat, sourceSeat int, fromZone string,
	allowRemotePublicSource bool) error {
	if publicPlayerZone(fromZone) && sourceSeat != actorSeat &&
		!allowRemotePublicSource {
		return newError(protocol.ErrApprovalRequired)
	}
	return nil
}

func normalizedOwnerSeat(card protocol.GameCard, fallback, seatCount int) int {
	if card.OwnerSeat >= 0 && card.OwnerSeat < seatCount {
		return card.OwnerSeat
	}
	return fallback
}

func validateOwnedCardDestination(actorSeat, ownerSeat int, fromZone, toZone string) error {
	if publicPlayerZone(fromZone) && ownerSeat != actorSeat &&
		toZone != protocol.ZoneBattlefield && !publicPlayerZone(toZone) {
		return newError(protocol.ErrInvalidTarget)
	}
	return nil
}

func normalizeLibraryPlacement(toZone string, placement *string, index *int,
	allowIndex bool) error {
	if toZone != protocol.ZoneLibrary {
		if *placement != "" || index != nil {
			return newError(protocol.ErrInvalidMove)
		}
		return nil
	}
	if *placement == "" {
		*placement = protocol.LibraryPlacementTop
	}
	switch *placement {
	case protocol.LibraryPlacementTop, protocol.LibraryPlacementBottom:
		if index != nil {
			return newError(protocol.ErrInvalidMove)
		}
	case protocol.LibraryPlacementIndex:
		if !allowIndex || index == nil || *index < 0 {
			return newError(protocol.ErrInvalidMove)
		}
	default:
		return newError(protocol.ErrInvalidMove)
	}
	return nil
}

func (r *Room) planCardMove(connID string, move *protocol.GameMoveCard) (cardMovePlan, error) {
	actorSeat, err := r.moveActor(connID)
	if err != nil {
		return cardMovePlan{}, err
	}
	if !validMoveZone(move.FromZone) || !validMoveZone(move.ToZone) {
		return cardMovePlan{}, newError(protocol.ErrInvalidZone)
	}
	if move.ToZone == protocol.ZoneSideboard ||
		(move.FromZone == protocol.ZoneSideboard &&
			move.ToZone != protocol.ZoneHand &&
			move.ToZone != protocol.ZoneBattlefield &&
			move.ToZone != protocol.ZoneGraveyard &&
			move.ToZone != protocol.ZoneExile) {
		return cardMovePlan{}, newError(protocol.ErrInvalidMove)
	}
	if (move.FromZone == protocol.ZoneCommand || move.ToZone == protocol.ZoneCommand) &&
		!protocol.IsCommanderFormat(r.Format) {
		return cardMovePlan{}, newError(protocol.ErrInvalidZone)
	}
	// A normal library projection does not reveal the top card. Reject this
	// hidden-to-command-zone path before inspecting the card so callers cannot
	// probe whether the unknown top card is a designated commander.
	if move.FromZone == protocol.ZoneLibrary && move.ToZone == protocol.ZoneCommand {
		return cardMovePlan{}, newError(protocol.ErrInvalidMove)
	}
	move.CardID = strings.TrimSpace(move.CardID)
	if move.FromZone != protocol.ZoneLibrary && move.CardID == "" {
		return cardMovePlan{}, newError(protocol.ErrInvalidMove)
	}
	move.FaceName = strings.TrimSpace(move.FaceName)
	if !validCardFaceName(move.FaceName) {
		return cardMovePlan{}, newError(protocol.ErrInvalidMove)
	}

	sourceSeat, err := r.moveSource(actorSeat, move.FromZone, move.FromSeat)
	if err != nil {
		return cardMovePlan{}, err
	}
	targetSeat := actorSeat
	if move.ToZone == protocol.ZoneBattlefield {
		if !validCardPosition(move.Position) {
			return cardMovePlan{}, newError(protocol.ErrInvalidPosition)
		}
		if move.ToSeat != nil {
			targetSeat = *move.ToSeat
		}
		if targetSeat < 0 || targetSeat >= len(r.Game.Seats) {
			return cardMovePlan{}, newError(protocol.ErrInvalidTarget)
		}
	} else if publicPlayerZone(move.ToZone) {
		if move.Position != nil {
			return cardMovePlan{}, newError(protocol.ErrInvalidPosition)
		}
		targetSeat = -1
		if move.ToSeat != nil {
			targetSeat = *move.ToSeat
			if targetSeat < 0 || targetSeat >= len(r.Game.Seats) {
				return cardMovePlan{}, newError(protocol.ErrInvalidTarget)
			}
		}
	} else if move.Position != nil || move.ToSeat != nil {
		return cardMovePlan{}, newError(protocol.ErrInvalidPosition)
	}
	if move.FaceDown && (move.ToZone != protocol.ZoneBattlefield ||
		(move.FromZone != protocol.ZoneHand && move.FromZone != protocol.ZoneLibrary)) {
		return cardMovePlan{}, newError(protocol.ErrInvalidMove)
	}
	if move.FromZone == move.ToZone &&
		(move.ToZone != protocol.ZoneBattlefield &&
			(!publicPlayerZone(move.ToZone) || move.ToSeat == nil ||
				sourceSeat == targetSeat)) {
		return cardMovePlan{}, newError(protocol.ErrInvalidMove)
	}
	if err := normalizeLibraryPlacement(move.ToZone, &move.LibraryPlacement,
		move.LibraryIndex, true); err != nil {
		return cardMovePlan{}, err
	}

	return cardMovePlan{
		actorSeat:  actorSeat,
		sourceSeat: sourceSeat,
		targetSeat: targetSeat,
	}, nil
}

func (r *Room) planCardBatchMove(connID string,
	move *protocol.GameMoveCards) (cardBatchMovePlan, error) {
	actorSeat, err := r.moveActor(connID)
	if err != nil {
		return cardBatchMovePlan{}, err
	}
	if move.FromZone != protocol.ZoneBattlefield && !publicPlayerZone(move.FromZone) {
		return cardBatchMovePlan{}, newError(protocol.ErrInvalidZone)
	}
	sourceSeat, err := r.moveSource(actorSeat, move.FromZone, move.FromSeat)
	if err != nil {
		return cardBatchMovePlan{}, err
	}

	targetSeat := -1
	if move.FromZone == protocol.ZoneBattlefield {
		if move.ToZone != protocol.ZoneLibrary &&
			move.ToZone != protocol.ZoneGraveyard &&
			move.ToZone != protocol.ZoneExile {
			return cardBatchMovePlan{}, newError(protocol.ErrInvalidZone)
		}
		if move.Position != nil || move.ToSeat != nil {
			return cardBatchMovePlan{}, newError(protocol.ErrInvalidMove)
		}
	} else {
		switch move.ToZone {
		case protocol.ZoneBattlefield:
			if !validCardPosition(move.Position) {
				return cardBatchMovePlan{}, newError(protocol.ErrInvalidPosition)
			}
			targetSeat = actorSeat
			if move.ToSeat != nil {
				targetSeat = *move.ToSeat
			}
		case protocol.ZoneHand, protocol.ZoneLibrary:
			if move.Position != nil || move.ToSeat != nil {
				return cardBatchMovePlan{}, newError(protocol.ErrInvalidMove)
			}
		case protocol.ZoneGraveyard, protocol.ZoneExile:
			if move.ToZone == move.FromZone {
				return cardBatchMovePlan{}, newError(protocol.ErrInvalidMove)
			}
			if move.Position != nil {
				return cardBatchMovePlan{}, newError(protocol.ErrInvalidPosition)
			}
			targetSeat = sourceSeat
			if move.ToSeat != nil {
				targetSeat = *move.ToSeat
			}
		default:
			return cardBatchMovePlan{}, newError(protocol.ErrInvalidZone)
		}
		if move.ToZone != protocol.ZoneHand && move.ToZone != protocol.ZoneLibrary &&
			(targetSeat < 0 || targetSeat >= len(r.Game.Seats)) {
			return cardBatchMovePlan{}, newError(protocol.ErrInvalidTarget)
		}
		if move.Randomize {
			return cardBatchMovePlan{}, newError(protocol.ErrInvalidMove)
		}
	}
	if err := normalizeLibraryPlacement(move.ToZone, &move.LibraryPlacement, nil, false); err != nil {
		return cardBatchMovePlan{}, err
	}
	if len(move.CardIDs) == 0 || len(move.CardIDs) > protocol.MaxDeckCards {
		return cardBatchMovePlan{}, newError(protocol.ErrInvalidMove)
	}

	selected := make(map[string]struct{}, len(move.CardIDs))
	cardIDs := make([]string, 0, len(move.CardIDs))
	for _, rawID := range move.CardIDs {
		cardID := strings.TrimSpace(rawID)
		if cardID == "" {
			return cardBatchMovePlan{}, newError(protocol.ErrInvalidMove)
		}
		if _, duplicate := selected[cardID]; duplicate {
			return cardBatchMovePlan{}, newError(protocol.ErrInvalidMove)
		}
		selected[cardID] = struct{}{}
		cardIDs = append(cardIDs, cardID)
	}

	return cardBatchMovePlan{
		actorSeat:  actorSeat,
		sourceSeat: sourceSeat,
		targetSeat: targetSeat,
		cardIDs:    cardIDs,
	}, nil
}
