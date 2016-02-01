# Using Notifications in Project:M36

Interactive applications should strive to show the most up-to-date data to the user. To that end, Project:M36 supports asynchronously-fired notifications sent from the database server to the client which fire when user-specified relational expressions change between transactions.

As an example, consider an email application. Users of the applications will want to know right away when new mail arrives, so polling every five minutes can cause a worst-case latency of five minutes for a new email to appear. Using asynchronous notifications in the database, the application is notified immediately upon transaction commit and can update accordingly without delay.

## What is a Notification?

A Project:M36 notification is comprised of three user-selected parts:

1. an arbitrary notification name: used to uniquely identify the notification in the server and client
2. a trigger relational expression: when the outcome of this relational expression changes between two transactions, the notification is fired
3. a report relational expression: when the notification fires, the expression is evaluated and passed along

By separating the "trigger" and "report" expressions, database users control what kind of reporting they receive when the outcome of a relational expression changes.

Currently, notifications are sent to all connected clients and not only to the client which created the notification. This may change in the future.

## Creating a Notification

Notifications can be created in the ```tutd``` TutorialD interpreter with the following syntax:

```
notify <notification name> <trigger relational expression> <report relational expression>
```

## Deleting a Notification

Notifications are uniquely identified by name and are shared among all clients. To delete a notification for all clients:

```
unnotify <notification name>
```

## A Motivating Example

Consider the following ```person``` relation variable where "name" is a key:

```
TutorialD (master): person:=relation{tuple{name "Steve",address "Main St."},tuple{name "John", address "Elm St."}}
TutorialD (master): :showexpr person
┌────────┬─────┐
│address │name │
├────────┼─────┤
│Elm St. │John │
│Main St.│Steve│
└────────┴─────┘
```

If a remote application is currently the address in the tuple for "Steve", then it would install a notification for that tuple's key:

```
TutorialD (master): notify steve_change person where name="Steve" (person where name="Steve"){address}
TutorialD (master): :commit
```

Then, when any client including the initiating client updates the "Steve" tuple, an asynchronous notification is fired:

```
TutorialD (master): update person where name="Steve" (address:="Grove St.")
TutorialD (master): :commit
TutorialD (master): Notification received "steve_change": ...
```

The notification contains the result from the evaluated report relational expression.
