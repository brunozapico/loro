#!/usr/bin/env python3
"""Adapt SwiftPM's generated resource lookup to a signed macOS bundle.

SwiftPM's CLI build emits Bundle.main.bundleURL/<resource>, but codesign
requires app resources under Contents/Resources. Patch only generated accessors
at compilation, after SwiftPM's planning has emitted them. The standalone CLI
still resolves resourceURL to its containing directory. No dependency sources
or runtime Foundation behavior are modified.
"""
import os
from pathlib import Path
import shlex
import sys


def expand(arguments):
    for argument in arguments:
        if argument.startswith('@') and Path(argument[1:]).is_file():
            yield from expand(shlex.split(Path(argument[1:]).read_text()))
        else:
            yield argument


for argument in expand(sys.argv[1:]):
    path = Path(argument)
    if path.name != 'resource_bundle_accessor.swift' or not path.is_file():
        continue
    original = path.read_text()
    updated = original.replace(
        'Bundle.main.bundleURL.appendingPathComponent(',
        '(Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent('
    )
    if updated != original:
        path.write_text(updated)

compiler = os.environ['LORO_SWIFTC']
os.execv(compiler, [compiler, *sys.argv[1:]])
