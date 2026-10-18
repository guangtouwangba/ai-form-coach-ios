#!/usr/bin/env python3
"""Create a temporary app copy with MLX preflight linked; never install/run it."""
from pathlib import Path
import shutil
import tempfile

root = Path(__file__).resolve().parents[4]
audit = Path(__file__).resolve().parents[1]
stage = Path(tempfile.mkdtemp(prefix='coach-qwen-combined-'))
for name in ['App', 'Sources', 'AIFormCoach.xcodeproj']:
    shutil.copytree(root / name, stage / name, ignore=shutil.ignore_patterns('xcuserdata'))
shutil.copy2(root / 'Package.swift', stage / 'Package.swift')
manifest = Path('Docs/Design/AI-Coach-Prototype/DESIGN-MANIFEST-v3.json')
(stage / manifest).parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(root / manifest, stage / manifest)
project = stage / 'AIFormCoach.xcodeproj/project.pbxproj'
s = project.read_text()
s = s.replace('/* Begin PBXBuildFile section */', '''/* Begin PBXBuildFile section */
        Q00000000000000000000001 = {isa = PBXBuildFile; productRef = Q00000000000000000000002; };''')
s = s.replace('                A00000000000000000000010,', '                A00000000000000000000010, Q00000000000000000000001,', 1)
s = s.replace('                D00000000000000000000004,', '                D00000000000000000000004, Q00000000000000000000002,', 1)
s = s.replace('                D00000000000000000000005,', '                D00000000000000000000005, Q00000000000000000000003,', 1)
s = s.replace('/* End XCLocalSwiftPackageReference section */', f'''        Q00000000000000000000003 = {{isa = XCLocalSwiftPackageReference; relativePath = "{audit / 'preflight'}"; }};
/* End XCLocalSwiftPackageReference section */''')
s = s.replace('/* End XCSwiftPackageProductDependency section */', '''        Q00000000000000000000002 = {isa = XCSwiftPackageProductDependency; package = Q00000000000000000000003; productName = CoachQwenPreflight; };
/* End XCSwiftPackageProductDependency section */''')
project.write_text(s)
app = stage / 'App/AIFormCoachApp.swift'
s = 'import CoachQwenPreflight\n' + app.read_text()
s = s.replace('struct AIFormCoachApp: App {', '''struct AIFormCoachApp: App {
    // Compile/link only: app is never launched by this audit.
    private let compileAuditLoader = CoachQwenPreflight.loadLocalWeights(at:)''')
app.write_text(s)
print(stage)
