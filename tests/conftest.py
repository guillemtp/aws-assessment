import json
import os
from pathlib import Path

import boto3
import pytest
from botocore.exceptions import ClientError


def pytest_addoption(parser):
    parser.addoption("--outputs-json", action="store", default="outputs.json")
    parser.addoption("--auth-region", action="store", default="us-east-1")
    parser.addoption("--username", action="store", default=None)
    parser.addoption("--password", action="store", default=None)


@pytest.fixture(scope="session")
def outputs_path(pytestconfig) -> Path:
    path = Path(pytestconfig.getoption("outputs_json") or os.getenv("OUTPUTS_JSON", "outputs.json"))
    if not path.exists():
        raise FileNotFoundError(f"Outputs file not found: {path}")
    return path


@pytest.fixture(scope="session")
def outputs(outputs_path):
    return json.loads(outputs_path.read_text(encoding="utf-8"))


@pytest.fixture(scope="session")
def username(pytestconfig):
    value = pytestconfig.getoption("username") or os.getenv("TEST_USERNAME")
    if not value:
        pytest.skip("Missing TEST_USERNAME")
    return value


@pytest.fixture(scope="session")
def password(pytestconfig):
    value = pytestconfig.getoption("password") or os.getenv("TEST_PASSWORD")
    if not value:
        pytest.skip("Missing TEST_PASSWORD")
    return value


@pytest.fixture(scope="session")
def auth_region(pytestconfig):
    return pytestconfig.getoption("auth_region") or os.getenv("AWS_REGION", "us-east-1")


@pytest.fixture(scope="session")
def id_token(outputs, auth_region, username, password):
    client_id = outputs["user_pool_client_id"]["value"]
    cognito = boto3.client("cognito-idp", region_name=auth_region)

    try:
        response = cognito.initiate_auth(
            ClientId=client_id,
            AuthFlow="USER_PASSWORD_AUTH",
            AuthParameters={"USERNAME": username, "PASSWORD": password},
        )
    except ClientError as exc:
        code = exc.response.get("Error", {}).get("Code")
        if code == "NotAuthorizedException":
            raise AssertionError(
                "Cognito authentication failed (incorrect username/password). "
                "If TEST_USER_PASSWORD was changed in .env, run `make tf-apply` to sync Cognito user password, "
                "then retry `make tests`."
            ) from exc
        raise

    if "AuthenticationResult" in response:
        return response["AuthenticationResult"]["IdToken"]

    raise RuntimeError(f"Unexpected Cognito auth response: {response}")


@pytest.fixture(scope="session")
def endpoints(outputs):
    return outputs["api_endpoints"]["value"]
