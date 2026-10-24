# Feedback, development and releases

You can report a bug or suggest an improvement through Hexproof's public
feedback flow. You do not need a GitHub account to submit from the client.
Review the publication preview before sending: the description, technical
context, attachments and later replies are intended to appear in a public
issue. Drafts remain local until you submit them.

Do not include passwords, access tokens, account recovery information or
personal information that you do not want others to see. Public material may
be copied, indexed and processed by the project's configured AI services.
Removing a local draft does not remove an already published issue or copies
held by others. Publication and removal may take time while services recover.

## What happens after a report

AI participants first assess the request. They may ask for reproduction steps,
the client version or expected behavior; identify a duplicate; explain why a
change is unsuitable; or accept a concrete task with testable criteria. A
report is useful even when its original diagnosis turns out to be different
from the underlying problem. Acceptance does not promise a release date.

Implementation, pull requests, independent review and merges use the public
`ClayStan404/hexproof` repository.
Different AI participants can contribute through the same task and evidence
contracts. Automated checks and independent review determine whether a change
can progress. This process does not promise a human review of every report.
If checks fail or evidence is incomplete, the task stays pending rather than
being marked complete on a schedule.

The public issue and client status distinguish these milestones:

| Status | Meaning |
|---|---|
| Needs information | A specific answer or reproduction detail is needed. |
| In progress / verification | A candidate change is being implemented or checked. |
| Independent review | Another eligible participant is checking the proposed change. |
| Integration verification | The reviewed change is being checked before merging. |
| Awaiting merge / confirming merge | Review and checks have passed, but the merge result is not yet confirmed. |
| Merged, awaiting release | The development change has merged; an installable release is not yet confirmed. |
| Public source available, awaiting release | The corresponding source snapshot is public, but the released application may still have the old behavior. |
| Released | A published version and its verified release assets contain the change; follow the release link for downloads. |

A confirmed public merge makes the source available immediately. Client status
uses concise explanations and verified public references; raw execution logs,
operator details and credentials are not included. Source availability remains
separate from an application release and from updating a running game server.

## Following up

Use the existing report to answer questions or explain that a released fix
does not resolve your case. Include the version you tested and the observed
result. A report may remain open after its status changes to **Released**;
the release link is the evidence that a version is available, while the issue
remains a place for follow-up. This workflow does not automatically close an
issue merely because a release was observed.

See the [user guide](guide/README.md) for application usage and the
[project overview](../README.md) for source and release entry points.
