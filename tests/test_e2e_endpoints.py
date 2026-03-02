import time

import httpx
import pytest


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


def _assert_region(expected_region, payload):
    actual_region = payload.get("region")
    assert actual_region == expected_region, (
        f"Region assertion failed. Expected {expected_region}, got {actual_region}. Payload: {payload}"
    )


@pytest.mark.parametrize("region", ["us-east-1", "eu-west-1"])
def test_greet_endpoint_by_region(endpoints, id_token, region):
    base_url = endpoints.get(region)
    assert base_url, f"Missing API endpoint for region {region}. Available: {sorted(endpoints.keys())}"

    _, status, latency_ms, payload = _call_api(region, "GET", f"{base_url}/greet", id_token)
    assert status == 200, f"/greet failed in {region}: status={status} payload={payload}"
    _assert_region(region, payload)
    print(f"[pytest:greet] region={region} status={status} latency_ms={latency_ms:.2f} payload={payload}")


@pytest.mark.parametrize("region", ["us-east-1", "eu-west-1"])
def test_dispatch_endpoint_by_region(endpoints, id_token, region):
    base_url = endpoints.get(region)
    assert base_url, f"Missing API endpoint for region {region}. Available: {sorted(endpoints.keys())}"

    _, status, latency_ms, payload = _call_api(region, "POST", f"{base_url}/dispatch", id_token)
    assert status == 200, f"/dispatch failed in {region}: status={status} payload={payload}"
    _assert_region(region, payload)
    print(f"[pytest:dispatch] region={region} status={status} latency_ms={latency_ms:.2f} payload={payload}")
