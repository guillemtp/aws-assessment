import concurrent.futures
import time

import httpx


def _call_api(region, method, url, token):
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }

    started = time.perf_counter()
    with httpx.Client(timeout=30.0) as client:
        response = client.request(method=method, url=url, headers=headers)
    elapsed_ms = (time.perf_counter() - started) * 1000

    try:
        payload = response.json()
    except ValueError:
        payload = {"raw": response.text}

    return region, response.status_code, elapsed_ms, payload


def _run_concurrently(plan, token):
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(plan)) as executor:
        futures = [executor.submit(_call_api, region, method, url, token) for region, method, url in plan]
        return [f.result() for f in concurrent.futures.as_completed(futures)]


def _assert_region(expected_region, payload):
    actual_region = payload.get("region")
    assert actual_region == expected_region, (
        f"Region assertion failed. Expected {expected_region}, got {actual_region}. Payload: {payload}"
    )


def test_greet_and_dispatch_endpoints(endpoints, id_token):
    greet_plan = [(region, "GET", f"{url}/greet") for region, url in endpoints.items()]
    dispatch_plan = [(region, "POST", f"{url}/dispatch") for region, url in endpoints.items()]

    greet_results = _run_concurrently(greet_plan, id_token)
    for region, status, latency_ms, payload in sorted(greet_results):
        assert status == 200, f"/greet failed in {region}: status={status} payload={payload}"
        _assert_region(region, payload)
        print(f"[pytest:greet] region={region} status={status} latency_ms={latency_ms:.2f} payload={payload}")

    dispatch_results = _run_concurrently(dispatch_plan, id_token)
    for region, status, latency_ms, payload in sorted(dispatch_results):
        assert status == 200, f"/dispatch failed in {region}: status={status} payload={payload}"
        _assert_region(region, payload)
        print(f"[pytest:dispatch] region={region} status={status} latency_ms={latency_ms:.2f} payload={payload}")
