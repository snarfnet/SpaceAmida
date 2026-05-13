import jwt, time, requests, os, hashlib
from PIL import Image, ImageFilter, ImageOps

KEY_ID = "WDXGY9WX55"
ISSUER = "2be0734f-943a-4d61-9dc9-5d9045c46fec"
LOC_ID = "643922ba-07b6-4527-bd87-8288658b1997"
IPHONE_SCREENSHOTS = ["screenshots/ss1.png", "screenshots/ss2.png", "screenshots/ss3.png"]
STATIC_SCREENSHOTS = ["screenshots/ss1_title.png", "screenshots/ss2_board.png", "screenshots/ss3_results.png"]
IPAD_SCREENSHOTS = ["screenshots/ipad_ss1.png", "screenshots/ipad_ss2.png", "screenshots/ipad_ss3.png"]

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

def err(r):
    try:
        return str(r.json())[:700]
    except Exception:
        return r.text[:700]

def source_screenshots():
    if all(os.path.exists(path) for path in IPHONE_SCREENSHOTS):
        return IPHONE_SCREENSHOTS
    return STATIC_SCREENSHOTS

def make_ipad_screenshots(sources):
    os.makedirs("screenshots", exist_ok=True)
    target = (2048, 2732)
    for src, dest in zip(sources, IPAD_SCREENSHOTS):
        image = Image.open(src).convert("RGB")
        background = ImageOps.fit(image, target, method=Image.Resampling.LANCZOS).filter(ImageFilter.GaussianBlur(42))
        overlay = Image.new("RGB", target, (4, 8, 18))
        background = Image.blend(background, overlay, 0.42)

        fitted = ImageOps.contain(image, (1680, 2520), method=Image.Resampling.LANCZOS)
        x = (target[0] - fitted.width) // 2
        y = (target[1] - fitted.height) // 2
        background.paste(fitted, (x, y))
        background.save(dest, "PNG")
        print(f"Generated {dest}: {target[0]}x{target[1]}")
    return IPAD_SCREENSHOTS

def delete_screenshot_set(display_type):
    r = api("GET", f"/appStoreVersionLocalizations/{LOC_ID}/appScreenshotSets")
    if r.status_code != 200:
        raise RuntimeError(f"Failed to list screenshot sets: {r.status_code} {err(r)}")
    for ss_set in r.json().get("data", []):
        if ss_set["attributes"]["screenshotDisplayType"] == display_type:
            set_id = ss_set["id"]
            r2 = api("GET", f"/appScreenshotSets/{set_id}/appScreenshots")
            for ss in r2.json().get("data", []):
                api("DELETE", f"/appScreenshots/{ss['id']}")
            api("DELETE", f"/appScreenshotSets/{set_id}")
            print(f"Deleted existing {display_type} set: {set_id}")

def existing_screenshot_set_is_ready(display_type, expected_count):
    r = api("GET", f"/appStoreVersionLocalizations/{LOC_ID}/appScreenshotSets")
    if r.status_code != 200:
        raise RuntimeError(f"Failed to list screenshot sets: {r.status_code} {err(r)}")
    for ss_set in r.json().get("data", []):
        if ss_set["attributes"]["screenshotDisplayType"] != display_type:
            continue
        set_id = ss_set["id"]
        r2 = api("GET", f"/appScreenshotSets/{set_id}/appScreenshots")
        screenshots = r2.json().get("data", []) if r2.status_code == 200 else []
        uploaded = []
        for ss in screenshots:
            attrs = ss.get("attributes") or {}
            delivery = attrs.get("assetDeliveryState") or {}
            if delivery.get("state") in (None, "COMPLETE"):
                uploaded.append(ss)
        if len(uploaded) >= expected_count:
            print(f"Keeping existing {display_type} set: {set_id} ({len(uploaded)} screenshots)")
            return True
    return False

def create_screenshot_set(display_type):
    r = api("POST", "/appScreenshotSets", json={"data": {
        "type": "appScreenshotSets",
        "attributes": {"screenshotDisplayType": display_type},
        "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": LOC_ID}}}
    }})
    if r.status_code not in (200, 201):
        raise RuntimeError(f"Failed to create {display_type} set: {r.status_code} {err(r)}")
    set_id = r.json()["data"]["id"]
    print(f"New {display_type} set: {set_id}")
    return set_id

def upload_screenshots(display_type, screenshots):
    if existing_screenshot_set_is_ready(display_type, len(screenshots)):
        return
    delete_screenshot_set(display_type)
    set_id = create_screenshot_set(display_type)

    for idx, path in enumerate(screenshots):
        if not os.path.exists(path):
            raise FileNotFoundError(path)
        data = open(path, "rb").read()
        fname = os.path.basename(path)

        r = api("POST", "/appScreenshots", json={"data": {
            "type": "appScreenshots",
            "attributes": {"fileName": fname, "fileSize": len(data)},
            "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}
        }})
        if r.status_code not in (200, 201):
            raise RuntimeError(f"Failed to create screenshot {fname}: {r.status_code} {err(r)}")
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
        if r.status_code not in (200, 201):
            raise RuntimeError(f"Failed to finish screenshot {fname}: {r.status_code} {err(r)}")
        print(f"  [{idx+1}] {fname}: {r.status_code}")

sources = source_screenshots()
upload_screenshots("APP_IPHONE_67", sources)
upload_screenshots("APP_IPAD_PRO_3GEN_129", make_ipad_screenshots(sources))
print("Done!")
