import XCTest
@testable import SharedFoundation

/// Tests for NoteTemplate variable substitution (defined in App target as TemplateStore.swift).
/// These tests cover the instantiate() logic independently of the UI.
///
/// NOTE: NoteTemplate lives in the App target, not SharedFoundation.
/// These tests will run in the MongrelNotesTests Xcode target (Layer 2).
/// This file is a STUB that documents the intent — copy it to Tests/ for Xcode.

/*
 The full TemplateInstantiationTests are written in:
   Tests/TemplateInstantiationTests.swift
 which runs under the MongrelNotesTests Xcode target where TemplateStore is reachable.
 */
