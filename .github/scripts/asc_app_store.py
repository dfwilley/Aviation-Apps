"""Show where an app stands in App Store Connect, or send a version to App Review.

  python3 asc_app_store.py status <bundle id>
  python3 asc_app_store.py submit <bundle id> <version> <build number or ""> "<what's new text>"

"status" only reads. "submit" does what the Submit for Review button does:
it makes the version if it isn't there yet, attaches the build, fills in the
"What's New" text if it is empty, and sends the version to App Review. The
version goes on sale by itself once Apple approves it.

Reads the App Store Connect API key from environment variables:
  ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt  # PyJWT

API = "https://api.appstoreconnect.apple.com/v1"
# A review submission in one of these states is still open.
OPEN_STATES = ("READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW", "UNRESOLVED_ISSUES")
# A version in one of these states can still be edited and submitted.
EDITABLE = ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
            "METADATA_REJECTED", "INVALID_BINARY")


class ApiError(Exception):
    pass


def token():
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"].strip(), "iat": now, "exp": now + 900,
         "aud": "appstoreconnect-v1"},
        os.environ["ASC_KEY_P8"],
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"].strip(), "typ": "JWT"},
    )


def call(method, path, body=None):
    req = urllib.request.Request(
        API + path, method=method,
        data=json.dumps(body).encode() if body else None,
        headers={"Authorization": "Bearer " + token(),
                 "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        raise ApiError(f"Apple API {method} {path} failed ({e.code}): {detail}")


def find_app(bundle_id):
    q = urllib.parse.quote(bundle_id)
    apps = [a for a in call("GET", f"/apps?filter[bundleId]={q}")["data"]
            if a["attributes"]["bundleId"] == bundle_id]
    if not apps:
        raise ApiError(f"No app with bundle ID {bundle_id} in App Store Connect.")
    return apps[0]


def versions(app_id):
    r = call("GET", f"/apps/{app_id}/appStoreVersions?limit=20&include=build")
    builds = {i["id"]: i["attributes"].get("version")
              for i in r.get("included", []) if i["type"] == "builds"}
    out = []
    for v in r["data"]:
        b = (v.get("relationships", {}).get("build", {}).get("data") or {}).get("id")
        out.append((v, builds.get(b)))
    return out


def builds(app_id):
    r = call("GET", f"/builds?filter[app]={app_id}&sort=-uploadedDate&limit=20"
                    "&include=preReleaseVersion")
    pre = {i["id"]: i["attributes"].get("version")
           for i in r.get("included", []) if i["type"] == "preReleaseVersions"}
    out = []
    for b in r["data"]:
        p = (b.get("relationships", {}).get("preReleaseVersion", {}).get("data") or {}).get("id")
        out.append((b, pre.get(p)))
    return out


def submissions(app_id):
    return call("GET", f"/reviewSubmissions?filter[app]={app_id}&filter[platform]=IOS&limit=20")["data"]


def state_of(v):
    a = v["attributes"]
    return a.get("appVersionState") or a.get("appStoreState")


def status(bundle_id):
    app = find_app(bundle_id)
    print(f"App: {app['attributes']['name']} ({bundle_id})")
    print("\nApp Store versions:")
    for v, build in versions(app["id"]):
        a = v["attributes"]
        print(f"  {a['versionString']}: {state_of(v)}, build attached: {build or 'none'}, "
              f"release: {a.get('releaseType')}, made {a.get('createdDate')}")
    print("\nUploaded builds (newest first):")
    for b, ver in builds(app["id"]):
        a = b["attributes"]
        print(f"  {ver} ({a['version']}): processing {a.get('processingState')}, "
              f"expired {a.get('expired')}, encryption answered "
              f"{a.get('usesNonExemptEncryption') is not None}, uploaded {a.get('uploadedDate')}")
    print("\nReview submissions:")
    subs = submissions(app["id"])
    for s in subs:
        print(f"  {s['attributes'].get('state')}, submitted {s['attributes'].get('submittedDate')}")
    if not subs:
        print("  none")


def submit(bundle_id, version, build_number, whats_new):
    app = find_app(bundle_id)
    app_id = app["id"]
    print(f"App: {app['attributes']['name']} ({bundle_id})")

    # 1. The build to send.
    usable = [(b, ver) for b, ver in builds(app_id)
              if ver == version and b["attributes"].get("processingState") == "VALID"
              and not b["attributes"].get("expired")
              and (not build_number or b["attributes"]["version"] == build_number)]
    if not usable:
        raise ApiError(f"No finished, unexpired build {build_number or '(any)'} of version "
                       f"{version} was found. Run this with 'status' to see what Apple has.")
    build = usable[0][0]
    print(f"Build to submit: {version} ({build['attributes']['version']})")
    if build["attributes"].get("usesNonExemptEncryption") is None:
        call("PATCH", f"/builds/{build['id']}", {"data": {
            "type": "builds", "id": build["id"],
            "attributes": {"usesNonExemptEncryption": False}}})
        print("Answered the encryption question for the build (no special encryption).")

    # 2. The App Store version.
    existing = versions(app_id)
    mine = [v for v, _ in existing if v["attributes"]["versionString"] == version]
    if mine:
        ver = mine[0]
        print(f"Version {version} already exists: {state_of(ver)}")
        if state_of(ver) not in EDITABLE:
            raise ApiError(f"Version {version} is {state_of(ver)}, so there is nothing to submit.")
    else:
        other = [v for v, _ in existing if state_of(v) in EDITABLE]
        if other:
            ver = other[0]
            old = ver["attributes"]["versionString"]
            call("PATCH", f"/appStoreVersions/{ver['id']}", {"data": {
                "type": "appStoreVersions", "id": ver["id"],
                "attributes": {"versionString": version}}})
            print(f"Renamed the unsubmitted version {old} to {version}.")
        else:
            ver = call("POST", "/appStoreVersions", {"data": {
                "type": "appStoreVersions",
                "attributes": {"platform": "IOS", "versionString": version,
                               "releaseType": "AFTER_APPROVAL"},
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]
            print(f"Made version {version}.")

    # 3. Attach the build.
    call("PATCH", f"/appStoreVersions/{ver['id']}/relationships/build",
         {"data": {"type": "builds", "id": build["id"]}})
    print("Attached the build to the version.")

    # 4. "What's New in This Version" (Apple requires it for an update).
    locs = call("GET", f"/appStoreVersions/{ver['id']}/appStoreVersionLocalizations")["data"]
    for loc in locs:
        if not (loc["attributes"].get("whatsNew") or "").strip():
            call("PATCH", f"/appStoreVersionLocalizations/{loc['id']}", {"data": {
                "type": "appStoreVersionLocalizations", "id": loc["id"],
                "attributes": {"whatsNew": whats_new}}})
            print(f"Filled in What's New for {loc['attributes'].get('locale')}.")

    # 5. Send it to App Review.
    open_subs = [s for s in submissions(app_id) if s["attributes"].get("state") in OPEN_STATES]
    waiting = [s for s in open_subs if s["attributes"]["state"] != "READY_FOR_REVIEW"]
    if waiting:
        raise ApiError("A review submission is already open "
                       f"({waiting[0]['attributes']['state']}). Nothing new was sent.")
    sub = open_subs[0] if open_subs else call("POST", "/reviewSubmissions", {"data": {
        "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
        "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]
    items = call("GET", f"/reviewSubmissions/{sub['id']}/items")["data"]
    if not items:
        call("POST", "/reviewSubmissionItems", {"data": {
            "type": "reviewSubmissionItems",
            "relationships": {
                "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub["id"]}},
                "appStoreVersion": {"data": {"type": "appStoreVersions", "id": ver["id"]}}}}})
    done = call("PATCH", f"/reviewSubmissions/{sub['id']}", {"data": {
        "type": "reviewSubmissions", "id": sub["id"], "attributes": {"submitted": True}}})
    print(f"Submitted for review. Apple's state: {done['data']['attributes'].get('state')}")


def main():
    try:
        if sys.argv[1] == "status":
            status(sys.argv[2])
        elif sys.argv[1] == "submit":
            submit(sys.argv[2], sys.argv[3].strip(), sys.argv[4].strip(), sys.argv[5].strip())
            print()
            status(sys.argv[2])
        else:
            sys.exit(__doc__)
    except ApiError as e:
        sys.exit(f"::error::{e}")


if __name__ == "__main__":
    main()
