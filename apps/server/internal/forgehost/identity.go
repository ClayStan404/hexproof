// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forgehost

// RuntimeID covers every native adapter source and reviewed upstream patch.
// Verify changes with third_party/forge-runtime/build-overlay.py --identity.
const RuntimeID = "0485ad49fb10c8ef5b3eda2a002c963d59be71dc-adapter27-f08ed2d01c01167abefcf311841a88697c8b0132348ae8431f9dfb094a7e474e"

// BaseRuntimeID is the immutable downloadable resource/dependency distribution.
// The packaged overlay supersedes its old adapter classes before starting Java.
const BaseRuntimeID = "0485ad49fb10c8ef5b3eda2a002c963d59be71dc-adapter25-e783b8c8739748ca7aadc00e79b6890e6cc509c0868e81113ef0613f259a421a"
