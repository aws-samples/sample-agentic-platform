"""
Standalone browser worker for Nova Act.

Called as a subprocess from the notebook to avoid the Windows Jupyter asyncio
limitation (ProactorEventLoop + nest_asyncio cannot spawn subprocesses).

Usage:
    python browser_worker.py --request "search query" --output result.json

The worker writes a JSON file with the result on success, or an error message
on failure. The calling notebook reads this file to inject results into memory.
"""
import argparse
import json
import os
import sys
import time

from dotenv import load_dotenv


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--request", required=True, help="Search request text")
    parser.add_argument("--output", required=True, help="Path to write JSON result")
    parser.add_argument("--region", default="us-east-1", help="AWS region")
    args = parser.parse_args()

    load_dotenv(".env")

    if "NOVA_ACT_API_KEY" not in os.environ:
        _write_error(args.output, "NOVA_ACT_API_KEY not found in environment")
        sys.exit(1)

    try:
        from bedrock_agentcore.tools.browser_client import browser_session
        from nova_act import NovaAct

        request = (
            args.request
            + " (do a very quick and brief search, the faster you return search "
            "results the better. For example, no need to click into the product "
            "description if you see the price on the main search results)"
        )

        with browser_session(args.region) as client:
            print("Browser session started... waiting for it to be ready.")
            time.sleep(5)

            ws_url, headers = client.generate_ws_headers()
            starting_url = "https://www.amazon.com"

            with NovaAct(
                cdp_endpoint_url=ws_url,
                cdp_headers=headers,
                nova_act_api_key=os.environ["NOVA_ACT_API_KEY"],
                starting_page=starting_url,
            ) as nova_act:
                # act_get() preserves the response field; act() erases it via .without_response()
                result = nova_act.act_get(prompt=request, max_steps=20)

                result_text = result.response if result.response else str(result)

                prompt_text = (
                    str(result.metadata.prompt)
                    if hasattr(result, "metadata") and hasattr(result.metadata, "prompt")
                    else args.request
                )

                output = {
                    "success": True,
                    "prompt": prompt_text,
                    "result": result_text,
                }
                _write_output(args.output, output)

    except Exception as e:
        import traceback
        _write_error(args.output, f"{e}\n{traceback.format_exc()}")
        sys.exit(1)


def _write_output(path, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)


def _write_error(path, message):
    _write_output(path, {"success": False, "error": message})


if __name__ == "__main__":
    main()
