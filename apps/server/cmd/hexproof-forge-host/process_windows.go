// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package main

import (
	"errors"
	"syscall"
	"unsafe"
)

// A private job covers the helper and all subsequently created JVMs. Keep its
// handle until process exit: a forced helper termination then closes the last
// handle and the kernel also terminates its Java child.
var hostingJob syscall.Handle

func initializeProcessGuard() error {
	kernel := syscall.NewLazyDLL("kernel32.dll")
	job, _, err := kernel.NewProc("CreateJobObjectW").Call(0, 0)
	if job == 0 {
		return err
	}
	type basicLimits struct {
		ProcessTime, JobTime                 int64
		Flags                                uint32
		MinimumWorkingSet, MaximumWorkingSet uintptr
		ActiveProcesses                      uint32
		Affinity                             uintptr
		Priority, Scheduling                 uint32
	}
	type extendedLimits struct {
		Basic                                                      basicLimits
		IO                                                         [6]uint64
		ProcessMemory, JobMemory, PeakProcessMemory, PeakJobMemory uintptr
	}
	limits := extendedLimits{Basic: basicLimits{Flags: 0x2000}} // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
	result, _, err := kernel.NewProc("SetInformationJobObject").Call(job, 9, uintptr(unsafe.Pointer(&limits)), unsafe.Sizeof(limits))
	if result == 0 {
		_ = syscall.CloseHandle(syscall.Handle(job))
		return err
	}
	process, err := syscall.GetCurrentProcess()
	if err != nil {
		_ = syscall.CloseHandle(syscall.Handle(job))
		return err
	}
	result, _, err = kernel.NewProc("AssignProcessToJobObject").Call(job, uintptr(process))
	if result == 0 {
		_ = syscall.CloseHandle(syscall.Handle(job))
		return errors.New("cannot contain hosting processes")
	}
	hostingJob = syscall.Handle(job)
	return nil
}
