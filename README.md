CENTOS ISO MAKER
================

By default, the process will download the centos ISO from the Internet.
But If you want you can use a local iso file, by simply puting it here, beside other files and directories like `build_iso.sh`.

```
./build_iso.sh --kickstart [kickstart name or regex]

    --kickstart       [kickstart name or regex]   --> (Mandatory)                             Define the kickstart filename (or path regex) to use. It must be present in kickstarts directory.
    --dest            [/path/to/tarball/dir/]     --> (optional, default: /home/amaibach/ISO) Local destination where the tarball will be stored.
    --release         [repository tag]            --> (optional, default: latest)             Allow to set the Saltstack project release to build for.
    --docker-img      [docker image path]         --> (optional, default: centos:latest)      Allow you to define which docker image to use for the build.
    --help | -h                                   --> (optional)                              Show this help.
```

- Example building with a regex

```bash
./build_iso.sh --kickstart '.*1810.*' --dest ~/Downloads/
```
