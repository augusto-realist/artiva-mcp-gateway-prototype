import uvicorn

from src.config import settings
from src.server import app

if __name__ == "__main__":
    uvicorn.run(app, host=settings.gateway_host, port=settings.gateway_port)
