# Manual Build and Auto Build instructions:

## Manual build:
```
docker build -t local/bitbucket:6.7.1  .
```

## Automated Build:

### Step 1: 
Make sure that this repo is connected to [https://cloud.docker.com](https://cloud.docker.com)

### Step 2: 
Create a new build rule for this automated build

In [https://cloud.docker.com](https://cloud.docker.com), create a new rule as follows:
* Source Type: Tag
* Source: /^[0-9.]+*$/
* Docker Tag: {sourceref}
* Dockerfile location: Dockerfile
* Build Context: / 
* Autobuild: On
* Build Caching: On


**Note:** The regex `/^[0-9.]+*$/` allows you to build docker images automatically for git tags such as: `6.7.1`, or `6.7.1-test` or `6.7.1.v-1.2` , etc.

### Step 3: 
* git add 
* git commit
* git tag 6.7.1-test
* git push && git push --tags

**Note:** `git push --tags` does not push commits to remote. So you need a separate `git push` as well.


# Manage git tags:

## List local tags:
```
$ git tag

6.3.0-v-1.0
6.5.1
6.7.1
6.7.1-test
6.7.1-v-2
6.7.1-v-3
6.7.1.1
```

## List remote tags:
```
$ git ls-remote --tags

From https://github.com/Praqma/bitbucket.git
ff99daf9edd230161042e431364692431b62b68b	refs/tags/6.3.0-v-1.0
86f730fef3b89559aeaa7bc81ff71d6c50a814d6	refs/tags/6.5.1
a5f7ebe688d5a56f51020b58c736ce403f1c3eed	refs/tags/6.7.1
de4dd8e78a6a08312c1cdcf510c983102b7f0acc	refs/tags/6.7.1-test
a09bf3f23aee42e50c93c0f917028c17d36352a7	refs/tags/6.7.1-v-2
c5012cfe5ba708fff63ef9b49ff66dad799cb46d	refs/tags/6.7.1-v-3
227de6f4470a4edde5babbe465a32b101fe0fb9d	refs/tags/6.7.1.1
```

## Deleting git tag from local repository: 
```
git tag -d 6.7.1-test
```

## Deleting git tag from remote repository: 
```
git push origin --delete 6.7.1-test
```



