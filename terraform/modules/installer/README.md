This config installs PTFE via Replicated onto a single EC2 instance in production mode and connected to an RDS instance for data persistence.

All resources required to support this instance are encapsulated here, from the VPC on up.

An Ubuntu Xenial AMI is chosen by default, but this config should remain distribution-agnostic.  For example, Amazon Linux.

## required variables

- `license_file` -- path to a Replicated license file
- `domain` -- domain the application will accessible at; used to look up existing Route 53 zone and wildcard ACM cert.

## optional variables

- `region` -- the region in which to create the AWS resources; defaults to `us-west-2`
- `ami` -- specific AMI ID to use. defaults to searching for the latest Ubuntu Xenial image
- `ssh_user` -- user to connect to the instance with, via ssh; defaults to `ubuntu`

## waiting for ready

    while ! curl -sfS --max-time 5 $( terraform output ptfe_health_check ); do sleep 5; done

## connecting via ssh

    ssh -F $( terraform output ssh_config_file ) default

