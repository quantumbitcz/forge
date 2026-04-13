# Amazon SageMaker — Training, Endpoints & Pipelines

## Overview

SageMaker provides managed ML infrastructure: training jobs, real-time endpoints, batch transforms, and ML pipelines. Use SageMaker Estimators to launch training jobs on managed compute, deploy models to endpoints for inference, and orchestrate multi-step workflows with SageMaker Pipelines. SageMaker integrates with S3 for data and artifact storage, ECR for custom containers, and IAM for access control.

## Architecture Patterns

### Training Jobs

```python
from sagemaker.estimator import Estimator

estimator = Estimator(
    image_uri="123456789.dkr.ecr.us-east-1.amazonaws.com/my-training:latest",
    role="arn:aws:iam::123456789:role/SageMakerExecutionRole",
    instance_count=1,
    instance_type="ml.m5.xlarge",
    output_path="s3://my-bucket/output/",
    hyperparameters={
        "learning_rate": 0.01,
        "epochs": 50,
        "batch_size": 32,
    },
    max_run=3600,
    tags=[{"Key": "project", "Value": "churn-prediction"}],
)
estimator.fit({"train": "s3://my-bucket/data/train/", "test": "s3://my-bucket/data/test/"})
```

Always specify `max_run` to prevent runaway training jobs. Tag all resources for cost tracking. Use explicit S3 paths for input data and output artifacts.

### Endpoints

```python
from sagemaker.model import Model

model = Model(
    image_uri="123456789.dkr.ecr.us-east-1.amazonaws.com/my-inference:latest",
    model_data="s3://my-bucket/output/model.tar.gz",
    role="arn:aws:iam::123456789:role/SageMakerExecutionRole",
)
predictor = model.deploy(
    initial_instance_count=1,
    instance_type="ml.m5.large",
    endpoint_name="churn-prediction-prod",
)
```

Use separate IAM roles for training and inference with least-privilege permissions. Always name endpoints explicitly — auto-generated names are hard to manage.

### SageMaker Pipelines

```python
from sagemaker.workflow.pipeline import Pipeline
from sagemaker.workflow.steps import TrainingStep, ProcessingStep

pipeline = Pipeline(
    name="churn-pipeline",
    steps=[preprocess_step, train_step, eval_step, register_step],
    parameters=[learning_rate_param, instance_type_param],
)
pipeline.upsert(role_arn=role)
execution = pipeline.start()
```

Define pipelines with parameterized steps for reusability. Use `ConditionStep` for branching logic (e.g., only register if evaluation metric exceeds threshold).

## Configuration

- Use SageMaker configuration files (`sagemaker.config.yaml`) for default settings (role, instance types, output paths).
- Set `SAGEMAKER_DEFAULT_S3_BUCKET` and `SAGEMAKER_DEFAULT_EXECUTION_ROLE` environment variables.
- Use SageMaker Local Mode (`instance_type="local"`) for development and debugging before running on managed infrastructure.
- Configure VPC settings for training jobs that need access to private data sources.
- Use Spot Instances (`use_spot_instances=True`) for training jobs to reduce costs by up to 90%.

## Performance

- Use the largest batch size that fits in GPU memory — SageMaker bills by instance-second.
- Enable SageMaker Debugger for training job profiling (GPU utilization, bottleneck detection).
- Use multi-instance training (`instance_count > 1`) with data-parallel or model-parallel strategies for large models.
- Configure auto-scaling for endpoints: scale to zero for dev/staging, scale based on invocations for production.
- Use SageMaker Inference Recommender to select the optimal instance type for endpoint latency and cost.

## Security

- Use least-privilege IAM roles — separate roles for training, inference, and pipeline execution.
- Enable VPC isolation for training jobs processing sensitive data.
- Use KMS keys for S3 encryption of training data and model artifacts.
- Never embed AWS credentials in training scripts — rely on the SageMaker execution role.
- Enable CloudTrail logging for all SageMaker API calls.
- Tag all resources with cost-center and project identifiers for billing visibility.

## Testing

- Use SageMaker Local Mode (`instance_type="local"`) for fast iteration without incurring cloud costs.
- Test custom containers locally with `docker run` before pushing to ECR.
- Validate pipeline definitions with `pipeline.definition()` — it returns the JSON without executing.
- Test endpoint inference with a sample payload before promoting to production.
- Use `sagemaker.Session(default_bucket="test-bucket")` in integration tests.

## Dos
- Set `max_run` on all training jobs to prevent runaway costs.
- Tag all SageMaker resources with project, team, and environment tags.
- Use Spot Instances for non-time-critical training jobs.
- Pin container image tags or SHA digests — never use `latest` in production.
- Use SageMaker Pipelines for multi-step workflows instead of ad-hoc script chaining.
- Store hyperparameters as pipeline parameters for experiment tracking and reproducibility.
- Enable auto-scaling on production endpoints.

## Don'ts
- Don't launch training jobs without `max_run` — unbounded jobs can accumulate massive costs.
- Don't use `ml.p3` or `ml.p4` instances for development — use Local Mode or `ml.m5` for debugging.
- Don't embed AWS credentials in source code or container images — use IAM roles.
- Don't deploy endpoints without configuring auto-scaling — idle endpoints incur continuous charges.
- Don't use the default SageMaker execution role for all jobs — create purpose-specific roles with least privilege.
- Don't skip VPC configuration for jobs processing sensitive or regulated data.
- Don't use `latest` tag for ECR container images in production — pin to a specific digest.
