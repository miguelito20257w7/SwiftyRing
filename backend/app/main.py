from fastapi import FastAPI

app = FastAPI(title="SwiftyRing API")


@app.get("/health")
def health():
    return {"status": "ok"}