// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

#pragma once

#include <atomic>
#include <memory>
#include <utility>

namespace hexproof::client {

class CatalogImportStopSource;

class CatalogImportStopToken final
{
  public:
    CatalogImportStopToken() = default;

    bool stopRequested() const noexcept
    {
        return m_requested && m_requested->load(std::memory_order_relaxed);
    }

  private:
    explicit CatalogImportStopToken(std::shared_ptr<const std::atomic_bool> requested)
        : m_requested(std::move(requested))
    {
    }

    std::shared_ptr<const std::atomic_bool> m_requested;

    friend class CatalogImportStopSource;
};

class CatalogImportStopSource final
{
  public:
    CatalogImportStopSource()
        : m_requested(std::make_shared<std::atomic_bool>(false))
    {
    }

    CatalogImportStopSource(const CatalogImportStopSource &) = delete;
    CatalogImportStopSource &operator=(const CatalogImportStopSource &) = delete;
    CatalogImportStopSource(CatalogImportStopSource &&) noexcept = default;
    CatalogImportStopSource &operator=(CatalogImportStopSource &&) noexcept = default;

    CatalogImportStopToken token() const noexcept
    {
        return CatalogImportStopToken(m_requested);
    }

    bool requestStop() noexcept
    {
        return m_requested && !m_requested->exchange(true, std::memory_order_relaxed);
    }

  private:
    std::shared_ptr<std::atomic_bool> m_requested;
};

} // namespace hexproof::client
