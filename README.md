README
====================

A simple script showing the megahit assembly example for the Nextflow framework.

## Run on a local machine
```{bash}
nextflow run -resume main.nf --seedfile 's3://genomics-workflow-core/Results/Megahit/2seedfile.csv' --output_path 's3://genomics-workflow-core/Results/Megahit/2samples' -profile docker
```

## Updated version with a seedfile as the input file
```{bash}
aws batch submit-job \
    --job-name nf-megahit \
    --job-queue priority-maf-pipelines \
    --job-definition nextflow-production \
    --container-overrides command="FischbachLab/nf-megahit, \
"--seedfile", "s3://genomics-workflow-core/Results/Megahit/2seedfile.csv", \
"--output_path", "s3://genomics-workflow-core/Results/Megahit/2samples" "
```
