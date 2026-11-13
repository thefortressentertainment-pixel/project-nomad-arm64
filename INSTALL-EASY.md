# Installing Project NOMAD (ARM64) — the easy way

Project NOMAD is an offline knowledge and education server. It puts
Wikipedia, Khan Academy lessons, maps, books, and an AI helper on your own
machine, so you can use them without the internet. This guide installs the
ARM64 version, which runs on ARM computers and phones. You do not need to
know GitHub, and you do not need to know how to code. You just need to be
able to copy and paste one command.

## What you need

- A computer or phone that runs **Debian or Ubuntu Linux on ARM** (for
  example a Raspberry Pi, an ARM server, or a phone running a Debian
  virtual machine — see "Installing on a phone" below). It also works on
  regular Intel/AMD computers running Debian or Ubuntu.
- An internet connection for the install itself. After that, NOMAD works
  offline.
- About 5 GB of free space for the smallest edition, more for the bigger
  ones (see "Choose your edition" below). The installer checks this for
  you and tells you which editions fit.
- A password for your computer (the installer needs administrator access
  for a few steps, and it will ask for your password).

## The one command

Open a terminal and copy and paste this whole line, then press Enter:

```sh
curl -fsSL https://raw.githubusercontent.com/thefortressentertainment-pixel/project-nomad-arm64/main/install.sh -o /tmp/nomad-arm-install.sh && bash /tmp/nomad-arm-install.sh
```

That downloads a small helper, which checks your machine, checks that the
NOMAD images are ready, and then runs the full installer.

## What happens next

1. The helper checks your computer and prints a few lines. If something
   is wrong (for example, you are not on Debian/Ubuntu), it will tell you
   plainly and stop.
2. The installer asks which edition to install (see below), and checks
   you have enough free space for it.
3. The installer asks two questions:
   - **"Are you sure you want to continue?"** — type `y` and press Enter.
   - **"I have read and accept the License Agreement?"** — type `y` and
     press Enter. (NOMAD is free, open-source software under the Apache
     License 2.0.)
4. If Docker is not installed, it installs it. Then it downloads NOMAD
   and starts it.
5. This takes a while on a first install — the downloads are large. On a
   phone it can take a lot longer, so be patient and leave it running.

## Choose your edition

NOMAD comes in editions that differ only in the offline content already
inside the image. The app itself is identical in every edition, and you
can always download more content later from inside NOMAD. Pick the one
that fits your device:

| Edition | What's inside | Needs at least |
|---|---|---|
| **standard** (the default) | Wikipedia top articles, CDC health guides, Medical Library — about 580 MB of content | 6 GB free |
| **lite** | A tiny Wikipedia (100 articles) — about 4 MB of content | 5 GB free |
| **comms** | Tiny Wikipedia plus Ham Radio questions and answers — about 80 MB; the Meshtastic and MeshCore apps are also downloaded ready, so they install instantly | 5 GB free |
| **full** | Everything above — about 740 MB of content | 7 GB free |
| **latest** | The plain image with no content built in (the original install) — you download what you want afterwards | 5 GB free |

If you are not sure, take **standard**. If your phone is short on space,
take **lite**. If you use mesh radios (Meshtastic or MeshCore), take
**comms**.

When it finishes, it prints an address. Open it in your web browser:

```
http://localhost:8080
```

That is NOMAD's Command Center. From there you can set it up, add
content, and use it. NOMAD starts by itself whenever your machine
restarts. If you ever need to start or stop it by hand, the installer
leaves helper scripts in `/opt/project-nomad/` called `start_nomad.sh`
and `stop_nomad.sh`.

## Installing on a phone

A phone cannot run NOMAD directly — it needs a small Debian virtual
machine running inside the phone first. That takes a bit of setting up,
and it is the fiddliest part of the whole thing. The step-by-step
instructions for the phone are in **README-ARM.md** in this repository.

Once the Debian virtual machine is running on your phone, open a terminal
inside it and run the same one command above. That is the only command
you need.

## What does not work on ARM

A few things from the regular version do not work on ARM computers:

- **Translate** (the translation service) — it only works on Intel/AMD.
- **Graphics-card AI** — the AI helper runs on the processor only, which
  is slower but works.
- Everything else — Wikipedia, lessons, maps, books, files, and the
  Command Center — works the same.

## If something goes wrong

- **"The Project NOMAD images have not been published yet"** — the
  installer checks this before it starts. It means the ready-made
  NOMAD images have not been built for this version yet. You need
  someone with access to the repository to run the three build
  workflows on GitHub first (Build Primary Docker Image, Build Sidecar
  Updater Image, and Build Disk Collector Image), each with a version
  number and "Also tag this image as :latest?" ticked. Then run the
  installer again. If you picked an edition other than the plain one
  (lite, standard, comms, or full), run the **Build Variant Docker
  Images** workflow instead — that is the one that publishes the
  editions.
- **"This installer only works on Debian or Ubuntu"** — you are not on
  a Debian-based system. Install Debian or Ubuntu first (on a phone,
  follow README-ARM.md).
- **The download fails halfway** — check your internet connection and
  run the command again. Downloads resume where they left off.
- **NOMAD does not open at http://localhost:8080** — wait a minute and
  try again; the first start takes a while. If it still does not open,
  check that Docker is running (`sudo systemctl status docker`) and
  look at the logs in `/opt/project-nomad/storage/logs/`.

## Where the files come from

The installer downloads everything from this repository
(`thefortressentertainment-pixel/project-nomad-arm64`). It is a
reverse-engineered ARM64 port of
[Crosstalk-Solutions/project-nomad](https://github.com/Crosstalk-Solutions/project-nomad)
v1.35.1, with multi-arch Docker images. The technical notes for the port
are in **README-ARM.md**.

Some large sample files (Wikipedia samples and icons) are stored in the
repository as small encoded blocks in `binary-blocks/` instead of as
regular files. If you downloaded this repository and those files are
missing, run `sh binary-blocks/restore-binaries.sh` from the repository
folder to rebuild them. The normal installer does not need this.
