from setuptools import setup, find_packages

setup(
    name="coinbase_ingestion_service",
    version="0.1.0",
    packages=find_packages(),
    install_requires=[
        "coinbase-advanced-py",
        "python-dotenv",
        "pydantic>=2.0",
        "pydantic-settings",
        "structlog",
        "prometheus-client",
        "backoff",
        "fastapi",
        "uvicorn",
    ],
) 