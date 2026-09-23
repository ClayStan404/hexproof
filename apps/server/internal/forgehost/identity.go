// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forgehost

// RuntimeID covers every native adapter source and reviewed upstream patch.
// Verify changes with third_party/forge-runtime/build-overlay.py --identity.
const RuntimeID = "2be4858216742009afe8a7cffb035fc7671e960d-adapter21-01f90de283a9d8421331ec4ab261e78c1958fb0063930a74267cb6b07cf9441e"

// BaseRuntimeID is the immutable downloadable resource/dependency distribution.
// The packaged overlay supersedes its old adapter classes before starting Java.
const BaseRuntimeID = "2be4858216742009afe8a7cffb035fc7671e960d-adapter2-d880a329b1cea98b0e32f0a6c38a6df9487fd3992e6150832fde2de08cec7446"
