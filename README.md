Powershell script that allows you to enter a target directory and a source directory, compare all files inside the directories, and report differences between the two.

If differences are detected it gives the option of synchronizing the target directory with the source directory, only synchronizing files that are missing or changed.
It does not remove files found in target that do not exist in source (will likely be added later).

It outputs results as a CSV file for further use.
