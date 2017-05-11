# NVIDIA driver docker volume

A tool to using NVIDIA GPU inside the docker container.

This tool inspired by [nvidia-docker](https://github.com/NVIDIA/nvidia-docker), but without any
other installation steps.

## How to use this tool

directly add the tool to `docker run` command.

```shell
docker run $(/path/to/nvidia_driver_docker_volume.sh) nvidia/cuda:8.0-cudnn5-devel-ubuntu14.04 bash
```

or you can run it first, then copy the output to the `docker run` command.

```shell
/path/to/nvidia_driver_docker_volume.sh
# below is the output of nvidia_driver_docker_volume.sh. This maybe different on your machine.
--device=/dev/nvidia0 --device=/dev/nvidiactl --device=/dev/nvidia-uvm --device=/dev/nvidia-uvm-tools --volume=/home/user1/.nvidia_docker/volume/nvidia_driver/375.39:/usr/local/nvidia:ro

# copy the above line to docker run command
docker run --device=/dev/nvidia0 ...... nvidia/cuda:8.0-cudnn5-devel-ubuntu14.04 bash
```

## Issues and Contributing

- Please let us known by [filing a new issue](https://github.com/djx339/nvidia_driver_docker_volume/issues/new)
- You can contribute by opening a [pull request](https://github.com/djx339/nvidia_driver_docker_volume/compare)
