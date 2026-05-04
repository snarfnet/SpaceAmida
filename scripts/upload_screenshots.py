import jwt, time, requests, os, hashlib

KEY_ID = "WDXGY9WX55"
ISSUER = "2be0734f-943a-4d61-9dc9-5d9045c46fec"
LOC_ID = "643922ba-07b6-4527-bd87-8288658b1997"
SCREENSHOTS = ["screenshots/ss1.png", "screenshots/ss2.png", "screenshots/ss3.png"]

p8 = open("/tmp/asc_key.p8").read()

def make_token():
    return jwt.encode(
        {"iss": ISSUER, "iat": int(time.time()), "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"},
        p8, algorithm="ES256", headers={"kid": KEY_ID}
    )

def h():
    return {"Authorization": f"Bearer {make_token()}", "Content-Type": "application/json"}

def api(method, path, **kwargs):
    return requests.request(method, f"https://api.appstoreconnect.apple.com/v1{path}", headers=h(), **kwargs)

# Delete existing screenshot sets
r = api("GET", f"/appStoreVersionLocalizations/{LOC_ID}/appScreenshotSets")
for ss_set in r.json().get("data", []):
    if ss_set["attributes"]["screenshotDisplayType"] == "APP_IPHONE_67":
        set_id = ss_set["id"]
        # Delete individual screenshots first
        r2 = api("GET", f"/appScreenshotSets/{set_id}/appScreenshots")
        for ss in r2.json().get("data", []):
            api("DELETE", f"/appScreenshots/{ss['id']}")
        api("DELETE", f"/appScreenshotSets/{set_id}")
        print(f"Deleted existing set: {set_id}")

# Create new screenshot set
r = api("POST", "/appScreenshotSets", json={"data": {
    "type": "appScreenshotSets",
    "attributes": {"screenshotDisplayType": "APP_IPHONE_67"},
    "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": LOC_ID}}}
}})
set_id = r.json()["data"]["id"]
print(f"New screenshot set: {set_id}")

for idx, path in enumerate(SCREENSHOTS):
    if not os.path.exists(path):
        print(f"  [{idx+1}] Not found: {path}")
        continue
    data = open(path, "rb").read()
    fname = os.path.basename(path)

    r = api("POST", "/appScreenshots", json={"data": {
        "type": "appScreenshots",
        "attributes": {"fileName": fname, "fileSize": len(data)},
        "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}
    }})
    ss = r.json()["data"]
    ss_id = ss["id"]
    for op in ss["attributes"]["uploadOperations"]:
        chunk = data[op["offset"]:op["offset"]+op["length"]]
        up_h = {h2["name"]: h2["value"] for h2 in op["requestHeaders"]}
        requests.put(op["url"], headers=up_h, data=chunk)

    md5 = hashlib.md5(data).hexdigest()
    r = api("PATCH", f"/appScreenshots/{ss_id}", json={"data": {
        "type": "appScreenshots", "id": ss_id,
        "attributes": {"uploaded": True, "sourceFileChecksum": md5}
    }})
    print(f"  [{idx+1}] {fname}: {r.status_code}")

print("Done!")
