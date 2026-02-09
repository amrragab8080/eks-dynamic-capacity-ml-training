FROM pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime

WORKDIR /workspace

# Install additional dependencies
RUN pip install --no-cache-dir \
    transformers \
    datasets \
    accelerate

# Copy training script
COPY train.py /workspace/train.py

ENTRYPOINT ["python", "/workspace/train.py"]
