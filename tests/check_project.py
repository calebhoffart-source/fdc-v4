from pathlib import Path
import plistlib
import re
p = Path(__file__).resolve().parents[1]
plistlib.loads((p / 'ios/Info.plist').read_bytes())
sources = [x for x in (p / 'ios').glob('*.swift')]
assert len(sources) >= 6, 'Missing Swift modules'
code = '\n'.join(s.read_text() for s in sources)
checks = {
    'native full-screen interface': 'TabView(selection:' in code and 'NavigationStack' in code,
    'camera AI': 'VNDetectHumanBodyPoseRequest' in code,
    '3 drill calibrations': 'case offense' in code and 'case defense' in code and 'case tackle' in code and 'samples.count >= 3' in code,
    'screen time photo audit': 'PhotosPicker' in code and 'VNRecognizeTextRequest' in code and 'CoachDate.yesterday' in code,
    'daily rep accountability': 'goalToday' in code and 'recordRep' in code,
    'notifications': 'UNUserNotificationCenter' in code,
    'voice commands': 'SFSpeechRecognizer' in code and 'AVSpeechSynthesizer' in code,
    'grades and study': 'GradebookScreen' in code and 'studyMinutesDue' in code,
    'travel loans': 'borrowForTravel' in code and 'travelDebt' in code,
    'replay local film': 'AVCaptureMovieFileOutput' in code and 'VideoPlayer' in code,
    'coach requests': 'CoachChatScreen' in code and 'CoachDialogue' in code,
    'focus challenge': 'FocusDriveScreen' in code,
    'season toggle': 'setSeason' in code,
    'weekly report': 'weeklySummary' in code,
    'offline storage': 'UserDefaults.standard.set' in code,
    'no paid APIs': not any(x in code for x in ['ManagedSettingsStore','FamilyActivityPicker','DeviceActivityCenter'])
}
for label, okay in checks.items():
    print(('PASS' if okay else 'FAIL') + ' ' + label)
assert all(checks.values())
assert 'IPHONEOS_DEPLOYMENT_TARGET' in (p/'project.yml').read_text()
print('Static package checks OK (not a real iOS compile).')
