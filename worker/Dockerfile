FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg fonts-dejavu-core ca-certificates && rm -rf /var/lib/apt/lists/*
RUN useradd --create-home factory
WORKDIR /app
COPY worker/factory.py /app/factory.py
USER factory
ENV PYTHONUNBUFFERED=1
CMD ["python", "factory.py"]
