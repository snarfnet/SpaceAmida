import jwt, time, requests, sys

KEY_ID = 'WDXGY9WX55'
ISSUER = '2be0734f-943a-4d61-9dc9-5d9045c46fec'
APP_ID = '6766202700'
BUILD_NUMBER = sys.argv[1]

p8 = open('/tmp/asc_key.p8').read()

def make_token():
    return jwt.encode(
        {'iss': ISSUER, 'iat': int(time.time()), 'exp': int(time.time()) + 1200, 'aud': 'appstoreconnect-v1'},
        p8, algorithm='ES256', headers={'kid': KEY_ID}
    )

def headers():
    return {'Authorization': f'Bearer {make_token()}', 'Content-Type': 'application/json'}

def api(method, path, **kwargs):
    r = requests.request(method, f'https://api.appstoreconnect.apple.com/v1{path}',
        headers=headers(), **kwargs)
    return r

def short_error(r):
    try:
        payload = r.json()
        errors = payload.get('errors') or []
        if errors:
            parts = []
            for err in errors[:3]:
                code = err.get('code', 'UNKNOWN')
                detail = err.get('detail') or err.get('title') or ''
                parts.append(f'{code}: {detail}')
                associated = (err.get('meta') or {}).get('associatedErrors') or {}
                for path, path_errors in associated.items():
                    for path_error in path_errors[:3]:
                        path_code = path_error.get('code', 'UNKNOWN')
                        path_detail = path_error.get('detail') or path_error.get('title') or ''
                        parts.append(f'{path} {path_code}: {path_detail}')
            return ' | '.join(parts)
    except Exception:
        pass
    return r.text[:500]

def delete_existing_version_submission(version_id):
    r = api('GET', f'/appStoreVersions/{version_id}/relationships/appStoreVersionSubmission')
    if r.status_code != 200:
        print(f'Could not check old version submission: {r.status_code} {short_error(r)}')
        return

    submission = (r.json().get('data') or {})
    submission_id = submission.get('id')
    if not submission_id:
        print('No old appStoreVersionSubmission found.')
        return

    print(f'Deleting old appStoreVersionSubmission: {submission_id}')
    r = api('DELETE', f'/appStoreVersionSubmissions/{submission_id}')
    if r.status_code not in (200, 204, 404):
        print(f'Old submission delete failed: {r.status_code} {short_error(r)}')

def submit_legacy(version_id):
    return api('POST', '/appStoreVersionSubmissions', json={
        'data': {
            'type': 'appStoreVersionSubmissions',
            'relationships': {
                'appStoreVersion': {
                    'data': {'type': 'appStoreVersions', 'id': version_id}
                }
            }
        }
    })

def reusable_review_submission_id():
    r = api('GET', f'/reviewSubmissions?filter[app]={APP_ID}&filter[platform]=IOS&limit=200')
    if r.status_code != 200:
        print(f'Could not list review submissions: {r.status_code} {short_error(r)}')
        return None

    submissions = r.json().get('data') or []
    print(f'Found reviewSubmissions: {len(submissions)}')
    for submission in submissions:
        state = (submission.get('attributes') or {}).get('state')
        submission_id = submission.get('id')
        print(f'ReviewSubmission {submission_id} state={state}')
        if state in ('WAITING_FOR_REVIEW', 'IN_REVIEW'):
            print(f'Already submitted for review: {submission_id} state={state}')
            sys.exit(0)
        if state == 'READY_FOR_REVIEW':
            return submission_id
    return None

def create_review_submission():
    r = api('POST', '/reviewSubmissions', json={
        'data': {
            'type': 'reviewSubmissions',
            'attributes': {'platform': 'IOS'},
            'relationships': {'app': {'data': {'type': 'apps', 'id': APP_ID}}}
        }
    })
    if r.status_code == 201:
        submission_id = r.json()['data']['id']
        print(f'ReviewSubmission created: {submission_id}')
        return submission_id, None

    existing_id = reusable_review_submission_id()
    if existing_id:
        print(f'Reusing reviewSubmission: {existing_id}')
        return existing_id, None

    return None, f'Create reviewSubmission failed: {r.status_code} {short_error(r)}'

def submit_review_submission(version_id):
    submission_id, error = create_review_submission()
    if not submission_id:
        return False, error

    r = api('POST', '/reviewSubmissionItems', json={
        'data': {
            'type': 'reviewSubmissionItems',
            'relationships': {
                'reviewSubmission': {'data': {'type': 'reviewSubmissions', 'id': submission_id}},
                'appStoreVersion': {'data': {'type': 'appStoreVersions', 'id': version_id}}
            }
        }
    })
    if r.status_code not in (200, 201):
        error = short_error(r)
        if 'already exists' not in error.lower() and 'already been taken' not in error.lower():
            return False, f'Add reviewSubmissionItem failed: {r.status_code} {error}'
        print(f'ReviewSubmissionItem already exists: {r.status_code}')
    else:
        print(f'Add item: {r.status_code}')

    r = api('PATCH', f'/reviewSubmissions/{submission_id}', json={
        'data': {
            'type': 'reviewSubmissions',
            'id': submission_id,
            'attributes': {'submitted': True}
        }
    })
    if r.status_code == 200:
        state = r.json()['data']['attributes']['state']
        return True, f'Submitted! State: {state}'
    return False, f'Submit failed: {r.status_code} {short_error(r)}'

print(f'Waiting for build {BUILD_NUMBER} to be processed...')
build_id = None
for i in range(80):
    r = api('GET', f'/builds?filter[app]={APP_ID}&filter[version]={BUILD_NUMBER}&filter[processingState]=VALID&limit=1')
    data = r.json()
    if data.get('data'):
        build_id = data['data'][0]['id']
        print(f'Build ready: {build_id}')
        break
    print(f'  Waiting... ({i+1}/80)')
    time.sleep(30)

if not build_id:
    print('WARNING: Build not found after 40 minutes. Check ASC manually.')
    sys.exit(1)

# Set export compliance
r = api('PATCH', f'/builds/{build_id}',
    json={'data': {'type': 'builds', 'id': build_id, 'attributes': {'usesNonExemptEncryption': False}}})
print(f'Export compliance: {r.status_code}')
if r.status_code not in (200, 204):
    print(f'Export compliance failed: {short_error(r)}')
    sys.exit(1)

# Find version - check all states
version_id = None
version_state = None
r = api('GET', f'/apps/{APP_ID}/appStoreVersions?filter[platform]=IOS&limit=1')
data = r.json()
if data.get('data'):
    version_id = data['data'][0]['id']
    version_state = data['data'][0]['attributes']['appStoreState']
    print(f'Found version: {version_id} state={version_state}')

if version_state in ('WAITING_FOR_REVIEW', 'IN_REVIEW'):
    print(f'Already in review ({version_state}). Nothing to do.')
    sys.exit(0)

if not version_id or version_state in ('READY_FOR_DISTRIBUTION',):
    print('Creating new version...')
    r = api('POST', '/appStoreVersions', json={
        'data': {
            'type': 'appStoreVersions',
            'attributes': {'platform': 'IOS', 'versionString': '1.0'},
            'relationships': {'app': {'data': {'type': 'apps', 'id': APP_ID}}}
        }
    })
    if r.status_code not in (200, 201):
        print(f'Failed to create version: {r.text[:300]}')
        sys.exit(1)
    version_id = r.json()['data']['id']
    version_state = 'PREPARE_FOR_SUBMISSION'

print(f'Version ID: {version_id} state={version_state}')

# Assign build
r = api('PATCH', f'/appStoreVersions/{version_id}/relationships/build',
    json={'data': {'type': 'builds', 'id': build_id}})
print(f'Build assigned: {r.status_code}')
if r.status_code not in (200, 204):
    print(f'Build assignment failed: {short_error(r)}')
    sys.exit(1)

delete_existing_version_submission(version_id)

# First submissions and rejected first releases can require the direct version
# submission endpoint. If Apple rejects that route, try the newer review
# submissions API and fail loudly if both routes are blocked.
r = submit_legacy(version_id)
if r.status_code in (200, 201):
    print('Submitted via appStoreVersionSubmissions.')
    sys.exit(0)

legacy_error = f'Legacy submit failed: {r.status_code} {short_error(r)}'
print(legacy_error)

ok, message = submit_review_submission(version_id)
print(message)
if ok:
    sys.exit(0)

print('Submission failed. Check App Store Connect version state and required metadata.')
sys.exit(1)
