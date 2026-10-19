# Security Policy

## Supported versions

Only the [latest release](https://github.com/Luis-Sejer/topside/releases/latest) receives security fixes.

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub: go to the [Security tab](https://github.com/Luis-Sejer/topside/security) and choose **Report a vulnerability**. Don’t open a public issue.

You can expect an acknowledgement within a few days and a fix or a plan as soon as the issue is understood.

## What the apps do with your data

- Nothing you do in the apps leaves your Mac. Each app asks GitHub whether a new version is out, and sends nothing about you.
- Settings are stored locally in each app's preferences (`dk.sejer.<app>`).
- Mirror uses the camera only while its popover is open. Nothing is recorded.
- Upnext reads your calendar on your Mac to find the next meeting and its link.
- Scrub and Beam read the clipboard: Scrub only when it holds a link, Beam only when you open its popover.
- Shelf keeps references to the files you drop on it, only while it runs.
- Drawer uses Accessibility to find and open other apps' menu bar icons, and, if you allow it, Screen Recording to show pictures of them. It pictures only the menu bar icons, and keeps those pictures in `~/Library/Application Support/Drawer`.
