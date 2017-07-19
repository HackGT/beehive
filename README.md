![](https://i.ytimg.com/vi/MmgKOjBfuBQ/maxresdefault.jpg)

# Why?

Biodomes is our deployment abstraction layer that lets us:

1. clearly and declaratively represent the **current** state of our deployment,
2. roll back to known working states if necessary,
3. have a clear audit trail when a deployment goes awry,
4. separate our deployment implementation details from normal developers,
5. and most importantly minimize manual changes to the infrastructure (through SSH, etc.).

We bascially get most of this for free with `git`, the rest is filled in with a handy
[travis job](https://travis-ci.org/HackGT/biodomes) that parses the files here and
translates them into one deployment configuration.

The goal here is to let everyone be able to deploy their apps and not have one person's
app destroy another! It's like each app lives in it's _own world_.

# Sounds Great! Tell me how.

It's pretty simple, the main unit here is the domain name on which your app runs.
Say you want to run an app that tells you if your phone is on silent or not on the
url `ismichaelsphoneoff.hack.gt`, simply make a file called `ismichaelsphoneoff.yaml`
in the top directory of this repository.

On the other hand you could provide this service for many people by making a folder called
`isyourphoneoff` and placing a `michael.yaml` and an `andrew.yaml` file there. This would make
`michael.isyourphoneoff.hack.gt` and `andrew.isyourphoneoff.hack.gt`.

NOTE: so far we can't go deeper with more subdomains, if you want support for this consider
contributing ;0

## Config File Format

```yaml
# a simple git ref on master:
git: https://github.com/HackGT/phonehome.git

# a more complex git
git:
    remote: https://github.com/HackGT/phonehome.git
    branch: master # optional
    rev: faceb00c  # optional, takes precedence over branch
    
# port the service will bind to, will be exposed through the `PORT` env var
# if none is given a port will be decided for you
target_port: 3000

# the port to expose externally (for http this is port 80)
# (optional) defaults to port 80 if nothing is given.
port: 80

# a list of dependent services, currently only supports `mongo`
# this is optional
wants:
    mongo: true

# a list of secrets to be given through environment variables.
# (optional) more on this in the secrets section...
secrets:
  - SESSION_SECRET

# environment variables passed to the program (optional)
env:
  EMAIL_FROM: "HackGT Team <hello@hackgt.com>"
  EMAIL_HOST: smtp.sendgrid.net
  EMAIL_PORT: 465
  PRODUCTION: true
  # turns into '["this can be","a list"]'
  WHITELIST:
    - this can be
    - a list
  # turns into '{"what":"is","going":"on"}'
  WEIRD_DATA:
    what: is
    going: on
```

At least one type of `git` is required. This will find the Docker Hub
image of the same name (`hackgt/phonehome`) and pull it.
If `rev` is specified it will pull the image with the tag of that `rev`,
if branch not specified or `master` it will pull the `latest` image,
if the branch is specified it will pull `latest-${branch name}`.

The deployment also gets these environment variables set by default:

1. `PORT` the port the service should bind to.

### Setting Secrets

Setting secrets is kind of a kludge right now. Say you have a secrets list in `dev/hacks.yaml`:
```yaml
secrets:
  - MY_SECRET
```

You have to go to the [Travis secrets page](https://travis-ci.org/HackGT/biodomes/settings)
and add an env var by the name of `DEV_HACKS_MY_SECRET`.
If the file is just in `/hacks.yaml` you must name it `DEFAULT_HACKS_MY_SECRET`.

**WARNING: your secret must be bash-escaped or Travis will do weird shit**

## Parting words

Hopefully this design will become more unified in the future.
But for now our priority is getting to a working state that can sustain itself for a long time
to come.
