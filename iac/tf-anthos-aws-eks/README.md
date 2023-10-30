## How to run

### TEST (devtesting)

```
    cd ~/bitbucket/ops/terraform-v2/probanx
    ./scripts/init_layer TEST compute/kubernetes test
    cd compute/kubernetes && terraform plan -var-file ./env/TEST.tfvars
    terraform apply -var-file ./env/TEST.tfvars
```


### STAGE EU

```
    cd ~/bitbucket/ops/terraform-v2/probanx
    ./scripts/init_layer stage.isx.money compute/kubernetes stage
    cd compute/kubernetes && terraform plan -var-file ./env/stage.isx.money.tfvars
    terraform apply -var-file ./env/stage.isx.money.tfvars
```