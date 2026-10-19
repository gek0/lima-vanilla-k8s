FROM python:3.13-slim
LABEL name="mburisa-vault-webapp-example"
LABEL maintainer="Matija Buriša <matijaburisa@gmail.com>"

COPY app.py requirements.txt ./

RUN pip install --no-cache-dir -r requirements.txt

EXPOSE 8000
CMD ["python", "app.py"]
