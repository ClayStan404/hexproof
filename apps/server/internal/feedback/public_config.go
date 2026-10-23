// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"fmt"
	"path/filepath"
	"regexp"
	"strings"
)

var repositoryPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9_.-]{1,100}$`)

var publicRevisionPattern = regexp.MustCompile(`^[A-Za-z0-9_.-]{1,80}$`)

type PublicConfig struct {
	PublicURL              string `json:"-"`
	DataDir                string `json:"dataDir"`
	Repository             string `json:"repository"`
	RepositoryID           int64  `json:"repositoryId"`
	PublisherActorID       int64  `json:"publisherActorId"`
	TokenFile              string `json:"tokenFile"`
	NoticeRevision         string `json:"noticeRevision"`
	NoticeText             string `json:"noticeText"`
	ProviderPolicyRevision string `json:"providerPolicyRevision"`
}

func (c PublicConfig) Validate(legacyDir string) error {
	if !filepath.IsAbs(c.DataDir) || filepath.Clean(c.DataDir) == filepath.Clean(legacyDir) || strings.HasPrefix(filepath.Clean(c.DataDir)+"/", filepath.Clean(legacyDir)+"/") || strings.HasPrefix(filepath.Clean(legacyDir)+"/", filepath.Clean(c.DataDir)+"/") {
		return fmt.Errorf("public and legacy stores must be separate")
	}
	if !repositoryPattern.MatchString(c.Repository) || c.RepositoryID < 1 || c.PublisherActorID < 1 || !filepath.IsAbs(c.TokenFile) || !publicRevisionPattern.MatchString(c.NoticeRevision) || !cleanText(c.NoticeText, 8192, true) || strings.TrimSpace(c.NoticeText) == "" || !publicRevisionPattern.MatchString(c.ProviderPolicyRevision) {
		return ErrInvalid
	}
	return nil
}

func (c PublicConfig) target() PublicTarget {
	return PublicTarget{Repository: c.Repository, RepositoryID: c.RepositoryID, PublisherActorID: c.PublisherActorID, PublicURL: c.PublicURL}
}
