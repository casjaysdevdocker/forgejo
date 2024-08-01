## 👋 Welcome to forgejo 🚀  

forgejo README  
  
  
## Install my system scripts  

```shell
 sudo bash -c "$(curl -q -LSsf "https://github.com/systemmgr/installer/raw/main/install.sh")"
 sudo systemmgr --config && sudo systemmgr install scripts  
```
  
## Automatic install/update  
  
```shell
dockermgr update forgejo
```
  
## Install and run container
  
```shell
mkdir -p "$HOME/.local/share/srv/docker/forgejo/rootfs"
git clone "https://github.com/dockermgr/forgejo" "$HOME/.local/share/CasjaysDev/dockermgr/forgejo"
cp -Rfva "$HOME/.local/share/CasjaysDev/dockermgr/forgejo/rootfs/." "$HOME/.local/share/srv/docker/forgejo/rootfs/"
docker run -d \
--restart always \
--privileged \
--name casjaysdevdocker-forgejo \
--hostname forgejo \
-e TZ=${TIMEZONE:-America/New_York} \
-v "$HOME/.local/share/srv/docker/casjaysdevdocker-forgejo/rootfs/data:/data:z" \
-v "$HOME/.local/share/srv/docker/casjaysdevdocker-forgejo/rootfs/config:/config:z" \
-p 80:80 \
casjaysdevdocker/forgejo:latest
```
  
## via docker-compose  
  
```yaml
version: "2"
services:
  ProjectName:
    image: casjaysdevdocker/forgejo
    container_name: casjaysdevdocker-forgejo
    environment:
      - TZ=America/New_York
      - HOSTNAME=forgejo
    volumes:
      - "$HOME/.local/share/srv/docker/casjaysdevdocker-forgejo/rootfs/data:/data:z"
      - "$HOME/.local/share/srv/docker/casjaysdevdocker-forgejo/rootfs/config:/config:z"
    ports:
      - 80:80
    restart: always
```
  
## Get source files  
  
```shell
dockermgr download src casjaysdevdocker/forgejo
```
  
OR
  
```shell
git clone "https://github.com/casjaysdevdocker/forgejo" "$HOME/Projects/github/casjaysdevdocker/forgejo"
```
  
## Build container  
  
```shell
cd "$HOME/Projects/github/casjaysdevdocker/forgejo"
buildx 
```
  
## Authors  
  
🤖 casjay: [Github](https://github.com/casjay) 🤖  
⛵ casjaysdevdocker: [Github](https://github.com/casjaysdevdocker) [Docker](https://hub.docker.com/u/casjaysdevdocker) ⛵  
