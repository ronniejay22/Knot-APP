"""
Deep Links & Universal Links — AASA Endpoint and Web Fallback

Step 9.1: Serves the Apple App Site Association (AASA) file for Universal Links
and provides a web fallback page for users without the app installed.

The AASA file tells iOS which URL patterns should open in the Knot app.
It must be served at /.well-known/apple-app-site-association (and optionally
at the root /apple-app-site-association) with Content-Type: application/json.

The web fallback at /recommendation/{id} renders a branded landing page
for users who open a recommendation link without the app installed.
"""

import html

from fastapi import APIRouter
from fastapi.responses import HTMLResponse, JSONResponse

# --- AASA Configuration ---

# Team ID + Bundle ID — must match the iOS app's provisioning profile
_APP_ID = "VN5G3R8J23.com.ronniejay.knot"

AASA_CONTENT = {
    "applinks": {
        "details": [
            {
                "appIDs": [_APP_ID],
                "components": [
                    {
                        "/": "/recommendation/*",
                        "comment": "Matches recommendation deep links",
                    }
                ],
            }
        ]
    },
    "webcredentials": {
        "apps": [_APP_ID]
    },
}

# --- Router ---

router = APIRouter(tags=["deeplinks"])


@router.get("/.well-known/apple-app-site-association")
async def aasa_well_known():
    """
    Serve the Apple App Site Association file at the standard path.

    Apple fetches this file when the app is installed to determine which
    URL patterns should open in the app instead of Safari. The response
    must be application/json with no .json file extension.
    """
    return JSONResponse(content=AASA_CONTENT, media_type="application/json")


@router.get("/apple-app-site-association")
async def aasa_root():
    """
    Serve the AASA file at the legacy root path.

    Apple checks both /.well-known/apple-app-site-association and
    /apple-app-site-association. This endpoint ensures compatibility.
    """
    return JSONResponse(content=AASA_CONTENT, media_type="application/json")


@router.get("/recommendation/{recommendation_id}")
async def recommendation_fallback(recommendation_id: str):
    """
    Web fallback page for recommendation deep links.

    When a user opens a recommendation URL without the Knot app installed,
    their browser hits this endpoint. It renders a branded landing page
    that directs them to install the app.

    When the app IS installed, iOS intercepts the URL before it reaches
    the browser — this endpoint is never hit in that case.
    """
    safe_id = html.escape(recommendation_id)
    page = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Knot — View Recommendation</title>
    <style>
        * {{ margin: 0; padding: 0; box-sizing: border-box; }}
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            background: linear-gradient(135deg, #1a0d26 0%, #0d0617 100%);
            color: white;
        }}
        .container {{
            text-align: center;
            padding: 40px 24px;
            max-width: 400px;
        }}
        .logo {{
            font-size: 48px;
            margin-bottom: 8px;
        }}
        h1 {{
            font-size: 28px;
            font-weight: 700;
            margin-bottom: 8px;
        }}
        .tagline {{
            color: #a0a0b0;
            font-size: 15px;
            margin-bottom: 32px;
        }}
        .card {{
            background: rgba(255, 255, 255, 0.06);
            border: 1px solid rgba(255, 255, 255, 0.1);
            border-radius: 16px;
            padding: 24px;
            margin-bottom: 24px;
        }}
        .card p {{
            color: #c0c0d0;
            font-size: 15px;
            line-height: 1.6;
        }}
        .badge {{
            display: inline-block;
            padding: 14px 32px;
            background: #e91e63;
            color: white;
            border-radius: 12px;
            text-decoration: none;
            font-weight: 600;
            font-size: 16px;
        }}
        .badge:hover {{ opacity: 0.9; }}
        .ref {{
            margin-top: 20px;
            color: #606070;
            font-size: 12px;
        }}
    </style>
</head>
<body>
    <div class="container">
        <div class="logo">\U0001F496</div>
        <h1>Knot</h1>
        <p class="tagline">Relational Excellence on Autopilot</p>
        <div class="card">
            <p>Someone shared a gift recommendation with you. Open this link on your iPhone with the Knot app installed to view it.</p>
        </div>
        <a href="#" class="badge">Coming Soon on the App Store</a>
        <p class="ref">Ref: {safe_id[:8] if len(safe_id) >= 8 else safe_id}</p>
    </div>
</body>
</html>"""
    return HTMLResponse(content=page, status_code=200)
