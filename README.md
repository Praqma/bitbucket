# Atlassian Software in Kubernetes (ASK) - BitBucket

This respository is a component of **[ASK](https://www.praqma.com/services/ask/) Atlassian Software in Kubernetes** ; and holds program-code to create Docker image for BitBucket. 

Although the title says "Atlassian Software in Kubernetes", the container image can be run on plain Docker/Docker-Compose/Docker-Swarm, etc. 

This image can be used to run a single / stand-alone  instance of BitBucket Software or a clustered setup known as BitBucket DataCenter. You simply need to enable certain environment variables to get that done.

The source-code in this repository is released under MIT License, but the actual docker container images (binaries) built by it are not. You are free to use this source-code to build your own BitBucket docker images and host them whereever you want. Please remember to consider various Atlassian and Oracle related lincense limitations when doing so.


## Getting Started

### Build:
First, you need to build the container image.

```shell
docker build -t local/bitbucket:version-tag .
```

### Usage:
In it's simplest form, this image can be used by executing:

```shell
$ docker run -p 7990:7990 -p 7999:7999 -d local/bitbucket:version-tag

CONTAINER ID        IMAGE             		COMMAND                  CREATED             STATUS              PORTS                    NAMES
1ffda5ff3a5a        local/bitbucket:versoin-tag "/docker-entrypoin..."   About a minute ago  Up About a minute   0.0.0.0:7990->7990/tcp   stoic_panini
```

If you want to set it up behind a reverse proxy, use the following command:

```shell
docker run \
  --name bitbucket \
  --p 7990:7990 \
  --p 7999:7999 \
  --e SERVER_SECURE=true  \
  --e SERVER_SCHEME=https \
  --e SERVER_PROXY_PORT=443 \
  --e SERVER_PROXY_NAME=bitbucket.example.com \
  --d local/bitbucket:version-tag
```

**Note:** When setting up BitBucket behind a (GCE/AWS/other) proxy/load balancer, make sure to setup proxy/load-balancer timeouts to large values such as 300 secs or more. (The default is set to 60 secs). It is **very** important to setup these timeouts, as BitBucket (and other atlassian software) can take significant time setting up initial database. Smaller timeouts will panic BitBucket setup process and it will terminate.

If you want to use a different BitBucket version, then simply change the version number in the Dockerfile, and rebuild the image.


## SSL Certificates

Supply additional certificates from a single mounted directory.

```shell
docker run \
    --name bitbucket \
    --publish 7990:7990 \
    --publish 7999:7999 \
    --volume /path/to/certificates:/var/atlassian/ssl \
    --detach \
    owner/image:tag
```

See `SSL_CERTS_PATH` ENV variable in [Dockerfile](Dockerfile).

You should see something like this when you run `docker logs bitbucket`.

```text
Importing certificate: /var/atlassian/ssl/eastwind.crt ...
Certificate was added to keystore
Importing certificate: /var/atlassian/ssl/northwind.crt ...
Certificate was added to keystore
Importing certificate: /var/atlassian/ssl/southwind.pem ...
Certificate was added to keystore
Importing certificate: /var/atlassian/ssl/westwind.pem ...
Certificate was added to keystore
```

## User provided plugins:
If you want to add plugins of your choice, you can list their IDs in `bitbucket-plugins.list` file , one plugin at each line. You can volume-mount this file inside the container as `/tmp/bitbucket-plugins.list` . The `docker-entrypoint.sh` script will process this file and install the plugins. You can customize the location of this file in Dockerfile by setting the PLUGINS_FILE environment var to a different location.

```shell
docker run \
  -p 7990:7990  \
  -p 7999:7999  \
  -v ${PWD}/bitbucket-plugins.list:/tmp/bitbucket-plugins.list \
  -d local/bitbucket:version-tag
```


## Environment variables

The following environment variables can be set when building your docker image.

| Env name | Description                                                                                                                                                                                                                                                                                                        | Defaults                              |
|------------------------------ |------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------     |---------------------------------      |
| BITBUCKET_VERSION                  | The version number which is part of the name of the bitbucket software bin/tarball/zip.                                                                                                                                                                                                                                    | 6.3.0                                 |
| DATACENTER_MODE               | This needs to be set to 'true' if you want to setup Bitbucket in a data-center mode. Need different lincense for this                                                                                                                                                                                                      | false                                 |
| BITBUCKET_DATACENTER_SHARE         | It needs to be a shared location, which multiple bitbucket instances can write to. This location will most probably be an NFS share, and should exist on the file system.  If it does not exist, then it will be created and chown to the bitbucket OS user.  NB: For this to work, DATACENTER_MODE should be set to true.      | /var/atlassian/bitbucket-datacenter        |
| TZ_FILE                       | Timezone. Set the path of the correct zone you want to use for your container. Can be set at runtime as well                                                                                                                                                                                                          | /usr/share/zoneinfo/Europe/Oslo       |
| OS_USERNAME   | Bitbucket bin-installer automatically creates a 'atlbitbucket' user and a 'bitbucket' group. Just specify what it's name is. | atlbitbucket     |
| OS_GROUPNAME  | Bitbucket bin-installer automatically creates a 'atlbitbucket' user and a 'bitbucket' group. Just specify what it's name is. | atlbitbucket     |
| BITBUCKET_HOME     | This is where run-time data will be saved. It needs persistent storage. This can be mounted on mount-point inside container. It needs to be owned by the same UID as of user bitbucket, normally UID 1000. The value if this variable should be same as 'app.bitbucketHome' in the bitbucket-response.varfile file. | /var/atlassian/application-data/bitbucket |
| BITBUCKET_INSTALL  | This is where Bitbucket software will be installed. Persistent storage is NOT needed. The value if this variable should be same as 'app.defaultInstallDir' in the bitbucket-response.varfile file. | /opt/atlassian/bitbucket |
| JAVA_OPTS | Optional values you want to pass as JAVA_OPTS. You can pass Java memory parameters to this variable, but in newer versionso of Atlassian software, memory settings are done in CATALINA_OPTS. |  |
| CATLINA_OPTS | CATALINA_OPTS will be used by BITBUCKET_INSTALL/bin/setenv.sh script . You can use this to setup internationalization options, and also any Java memory settings. It is a good idea to use same value for -Xms and -Xmx to avoid frequence shrinking and expanding of Java memory. e.g. `CATALINA_OPTS "-Dfile.encoding=UTF-8 -Xms1024m -Xmx1024m"` . The memory values should always be half (or less) of physical RAM of the server/node/pod/container. | `CATALINA_OPTS "-Dfile.encoding=UTF-8 -Xms1024m -Xmx1024m"` |
| SERVER_PROXY_NAME | The FQDN used by anyone accessing bitbucket from outside (i.e. The FQDN of the proxy server/ingress controller) | bitbucket.example.com |
| SERVER_PROXY_PORT | The public facing port, not the bitbucket container port | `443` |
| SERVER_SCHEME | The scheme used by the public facing proxy - normally https. | `https` |
| SERVER_CONTEXT_PATH | The context path, if any. Best to leave blank.   | `/`|


## Linter

You can use a linter that analyze source code to flag programming errors, bugs, stylistic errors, and suspicious constructs. There is [dockerlinter](https://github.com/RedCoolBeans/dockerlint) , which does this quite easily.

### Installation
```
$ sudo npm install -g dockerlint
```

### Usage:
```
dockerlint Dockerfile
```

Above command will parse the file and notify you about any actual errors (such an omitted tag when : is set), and warn you about common pitfalls or bad idiom such as the common use case of ADD. In order to treat warnings as errors, use the -p flag.


