import asyncio
import gc
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from PIL import Image

import main


class _MemoryUpload:
    filename = "short.png"

    def __init__(self, data: bytes):
        self._data = io.BytesIO(data)

    async def read(self, size: int = -1) -> bytes:
        return self._data.read(size)


class LongScreenshotTests(unittest.TestCase):
    def test_fully_refunded_order_and_refund_are_both_ignored(self):
        base = {"merchant": "美团", "type": "expense", "amountCents": 2991}
        remaining, ignored = main._cancel_balanced_pairs([
            {**base, "note": "已全额退款"},
            {**base, "type": "income", "description": "退款"},
            {**base, "amountCents": 2690},
            {**base, "note": "退款申请中"},
            {**base, "note": "部分退款"},
            {**base, "note": "退款失败"},
        ])
        self.assertEqual(ignored, 2)
        self.assertEqual(len(remaining), 4)
        self.assertEqual(remaining[0]["amountCents"], 2690)

    def test_overlap_merge_preserves_refund_status(self):
        base = {"merchant": "美团", "type": "expense", "amountCents": 2991,
                "transactionTime": "2026-09-04T09:09:00"}
        merged = main._merge_duplicate_candidates([
            {**base, "_slice": 0, "note": "已全额退款"},
            {**base, "_slice": 1, "note": "这是另一张切片识别出的较长普通订单备注"},
        ])
        remaining, ignored = main._cancel_balanced_pairs(merged)
        self.assertEqual(ignored, 1)
        self.assertEqual(remaining, [])

    def test_slice_boxes_cover_long_image_with_overlap(self):
        boxes = main._plan_slice_boxes(1200, 12281)

        self.assertGreater(len(boxes), 1)
        self.assertEqual(boxes[0][0], 0)
        self.assertEqual(boxes[-1][1], 12281)
        for previous, current in zip(boxes, boxes[1:]):
            self.assertLess(current[0], previous[1])
            self.assertLess(current[0], current[1])

    def test_adjacent_duplicate_keeps_more_complete_text(self):
        candidates = [
            {
                "_slice": 0,
                "type": "expense",
                "amountCents": 300000,
                "merchant": "嘉恒广",
                "transactionTime": "2026-08-17T17:31:00",
                "timeConfident": False,
                "parseWarnings": ["边缘行"],
            },
            {
                "_slice": 1,
                "type": "expense",
                "amountCents": 300000,
                "merchant": "嘉恒广场房租",
                "transactionTime": "2026-08-17T17:31:00",
                "timeConfident": True,
                "parseWarnings": [],
            },
        ]

        merged = main._merge_duplicate_candidates(candidates)

        self.assertEqual(len(merged), 1)
        self.assertEqual(merged[0]["merchant"], "嘉恒广场房租")
        self.assertTrue(merged[0]["timeConfident"])
        self.assertNotIn("_slice", merged[0])

    def test_non_adjacent_same_bill_is_not_merged(self):
        base = {
            "type": "expense",
            "amountCents": 300,
            "merchant": "宁波地铁",
            "transactionTime": "2026-08-10T08:00:00",
            "parseWarnings": [],
        }
        merged = main._merge_duplicate_candidates([
            {**base, "_slice": 0},
            {**base, "_slice": 2},
        ])

        self.assertEqual(len(merged), 2)

    def test_refund_is_ignored_without_deleting_expenses(self):
        base = {
            "amountCents": 8800,
            "currency": "CNY",
            "merchant": "网购商户",
        }
        remaining, cancelled = main._cancel_balanced_pairs([
            {**base, "type": "expense", "transactionTime": "2026-08-01T10:00:00"},
            {**base, "type": "expense", "transactionTime": "2026-08-02T10:00:00"},
            {**base, "type": "income", "categoryId": "refund", "transactionTime": "2026-08-02T11:00:00"},
        ])

        self.assertEqual(cancelled, 1)
        self.assertEqual(len(remaining), 2)
        self.assertTrue(all(item["type"] == "expense" for item in remaining))

    def test_failed_middle_slice_does_not_make_outer_slices_adjacent(self):
        base = {
            "type": "expense",
            "amountCents": 300,
            "merchant": "宁波地铁",
            "transactionTime": "2026-08-10T08:00:00",
            "parseWarnings": [],
        }

        def recognize(path: Path) -> str:
            if path.name == "slice-1":
                raise main.qwen_client.QwenError("模拟单片失败")
            return path.name

        with (
            patch.object(main, "_ocr_slice_with_retry", side_effect=recognize),
            patch.object(main, "_run_parse_many", return_value=[dict(base)]),
        ):
            _, merged = main._recognize_slices(
                [Path("slice-0"), Path("slice-1"), Path("slice-2")],
                "2026-08-28T21:00:00",
            )

        self.assertEqual(len(merged), 2)

    def test_short_screenshot_uses_original_path_and_cleans_up_safely(self):
        image = Image.new("RGB", (600, 800), "white")
        buffer = io.BytesIO()
        image.save(buffer, format="PNG")
        candidate = {
            "type": "expense",
            "amountCents": 100,
            "categoryId": "other",
            "sourceType": "screenshot",
            "confidence": 0.85,
        }

        with (
            patch.object(main.qwen_client, "understand_image", return_value="一笔账单"),
            patch.object(main, "_run_parse_many", return_value=[candidate]),
        ):
            response = asyncio.run(
                main.parse_screenshot(
                    _MemoryUpload(buffer.getvalue()),
                    referenceTime="2026-08-28T21:00:00",
                    merchantRules=None,
                )
            )

        self.assertEqual(response["candidates"], [candidate])

    def test_estimate_increases_with_media_size_or_duration(self):
        with tempfile.TemporaryDirectory() as raw_dir:
            temp_dir = Path(raw_dir)
            short = temp_dir / "short.png"
            long = temp_dir / "long.png"
            Image.new("RGB", (600, 800), "white").save(short)
            Image.new("RGB", (600, 6000), "white").save(long)

            self.assertGreater(
                main._estimate_screenshot_seconds([long]),
                main._estimate_screenshot_seconds([short]),
            )
            self.assertGreater(
                main._estimate_audio_seconds(120),
                main._estimate_audio_seconds(10),
            )

    def test_persistent_job_completes_with_partial_image_failure(self):
        candidate = {
            "type": "expense",
            "amountCents": 1880,
            "categoryId": "food",
            "sourceType": "screenshot",
            "confidence": 0.85,
        }
        with tempfile.TemporaryDirectory() as raw_dir:
            temp_dir = Path(raw_dir)
            data_dir = temp_dir / "job_data"
            job_id = "test-job"
            first = data_dir / job_id / "first.png"
            second = data_dir / job_id / "second.png"
            first.parent.mkdir(parents=True)
            first.write_bytes(b"first")
            second.write_bytes(b"second")

            def recognize(path: Path, _: str, merchant_rules=None):
                if path.name == "first.png":
                    raise main.HTTPException(status_code=422, detail="第一张不可读")
                return "第二张账单", [candidate]

            with (
                patch.object(main, "JOB_DB_PATH", temp_dir / "jobs.sqlite3"),
                patch.object(main, "JOB_DATA_DIR", data_dir),
                patch.object(main, "_process_screenshot_path", side_effect=recognize),
            ):
                main._init_job_store()
                main._insert_job(
                    job_id,
                    "screenshot",
                    30,
                    {
                        "paths": [str(first), str(second)],
                        "referenceTime": "2026-08-28T21:00:00",
                    },
                )
                main._run_recognition_job(job_id)
                with main._job_connection() as connection:
                    row = connection.execute(
                        "SELECT status, result_json FROM recognition_jobs WHERE id = ?",
                        (job_id,),
                    ).fetchone()
                connection.close()

            self.assertEqual(row["status"], "completed")
            result = json.loads(row["result_json"])
            self.assertEqual(result["candidates"], [candidate])
            self.assertEqual(result["imageErrors"], ["第一张不可读"])
            self.assertFalse((data_dir / job_id).exists())
            del row
            gc.collect()


if __name__ == "__main__":
    unittest.main()
