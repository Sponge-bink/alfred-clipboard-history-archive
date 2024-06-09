# Clipboard History Archive for Alfred

Backup Alfred’s clipboard history so it doesn’t expire!

Alfred’s Clipboard History can only keep items copied within 3 months at most. With this workflow you can have unlimited amount of items ready to search for. 

This workflow lets you backup data from Alfred’s Clipboard History (only texts will be backed up). Merge the backed up data to a master database (without duplications). And search in the master database. 

*You will need to specify a directory first. Inside the ‘Configure Workflow…’ button, find ‘Backup to’ option and select a folder you want to backup to.*

## Backup

Invoke the `clipboardarchive` keyword (can be customized inside ‘Configure Workflow…’ button) and choose ‘Backup to …’ option.

All your data will be backed up to the directory you specified inside ‘Configure Workflow…’. A new ‘all.sqlite3’ database will be created to store all backed up items from now on if you have no backups.

![](images/3.png)

![](images/6.png)

## Check Status

Shows you how many items are currently in Alfred’s Clipboard History database and your master database (if you have backed up before).

Invoke the `clipboardarchive` keyword (can be customized inside ‘Configure Workflow…’ button) and choose ‘Status of …’ option.

![](images/4.png)

![](images/5.png)

## Search

Invoke the `pp` keyword (can be customized inside ‘Configure Workflow…’ button) or the hotkey ⌘⌥X (can be customized by editing the Hotkey object) and start typing. 

![](images/1.png)

Clipboard items matching your query will show in the result. 

![](images/2.png)

You can hit return to copy the item to clipboard or hit ⌘ return to view the item in Alfred’s Text View (Alfred 5.5 required). You can get right back to the previous window by pressing Esc.

![](images/7.png)

![](images/8.png)

Inspired by a [topic](https://www.alfredforum.com/topic/10969-keep-clipboard-history-forever/?do=findComment&comment=68859) on the Alfred Forum. The backup function is base on an modified version of [theSquashSH](https://www.alfredforum.com/profile/4058-thesquashsh/)’s [script](https://gist.github.com/pirate/6551e1c00a7c4b0c607762930e22804c).
