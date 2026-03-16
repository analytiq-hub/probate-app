from fastapi import FastAPI


app = FastAPI(title="Probate API", version="0.1.0")


@app.get("/health", tags=["health"])
async def health() -> dict:
    return {"status": "ok"}

