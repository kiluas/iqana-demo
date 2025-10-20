from __future__ import annotations

import json
import time
from decimal import Decimal
from typing import Any, cast

import boto3
from mypy_boto3_dynamodb import DynamoDBServiceResource
from mypy_boto3_dynamodb.service_resource import Table
from mypy_boto3_dynamodb.type_defs import GetItemOutputTypeDef


def _json_to_ddb_numbers(payload: Any) -> Any:
    """Convert floats to Decimal so boto3 can persist them in DynamoDB."""
    return json.loads(json.dumps(payload), parse_float=Decimal)


class HoldingsCache:
    def __init__(self, table_name: str, client: DynamoDBServiceResource | None = None) -> None:
        self.table_name = table_name

        # Fully typed resource & table
        self.dynamodb = client or boto3.resource("dynamodb")  # type: ignore  # noqa: PGH003
        self.table: Table = self.dynamodb.Table(table_name)  # type: ignore  # noqa: PGH003

    @staticmethod
    def _pk(user_id: str) -> str:
        return f"holdings#{user_id}"

    def read(self, user_id: str) -> dict[str, Any] | None:
        resp: GetItemOutputTypeDef = self.table.get_item(Key={"pk": self._pk(user_id)})  # type: ignore  # noqa: PGH003

        item = cast(dict[str, Any] | None, resp.get("Item"))
        if not item:
            return None

        ttl_raw = item.get("ttl")
        # Be tolerant: Dynamo might store int/Decimal/string
        ttl = int(ttl_raw) if ttl_raw is not None else 0
        if ttl and ttl < int(time.time()):
            return None

        payload = cast(dict[str, Any] | None, item.get("payload"))
        return payload

    def write(self, user_id: str, payload: dict[str, Any], ttl_seconds: int) -> None:
        now = int(time.time())
        doc: dict[str, Any] = {
            "pk": self._pk(user_id),
            "ttl": now + ttl_seconds,
            "payload": _json_to_ddb_numbers(payload),
        }
        # Return type is typed in stubs; we don't need it here.
        self.table.put_item(Item=doc)
