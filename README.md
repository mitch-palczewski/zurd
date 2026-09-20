# The Terror of the all consuming *Zurd*
Developed by the Feed Collective: Eben Kling, Aude Jomini, Phil Lique, Mitch Palczewski

# Set up
### Required Applications 
- [.NET SDK](https://dotnet.microsoft.com/en-us/download) - Allows you to run Godot Engine with C# 
- [Godot Engine - .NET](https://godotengine.org/download/windows/) - Make sure to select the .NET version
- [IDE like Visual Studio Code](https://code.visualstudio.com/) - Allows the editing of scripts and github integration

## Running the project
### Cloning the project in Visual Studio Code
1. In VSCode open the desired workspace folder (**File -> Open Folder**).
> Note: Cloning the repository will automatically create a child folder for the project to live in.
> For Example create a folder called zurd-worspace and navigate to it in your IDE then clone the repo into it. A workspace folder is a great place to include sketches and material that is associated or yet to make it into the project.
2. Clone the repository. To clone the repository in VS code, in the top left navigate to **Terminal -> New Terminal**. Paste the following command into the terminal and press **Enter**. You should see a new folder called *Zurd* appear in your directory. This contains the project files. 
```
git clone https://github.com/mitch-palczewski/zurd.git
cd zurd
```
3. Open the *Zurd* folder in VS Code. Again go to **File -> Open Folder** and select the newly create *Zurd* folder.
> Success you are all set up in VS code. This is where you will be making git commits and editing scripts.

### Opening the project in Godot 
1. Open Godot (the .net version)
2. Select *Import* in the top left.
3. Navigate to the *Zurd* folder cloned in the previous step and *Select Current Folder*
> Import and Godot will open up the project

# Git Commits
## How to commit in VS Code 
1. After making changes to the project navigate to the *Source Control* tab on the upper left hand side (the three dots connected with a branch).
2. Stage the files you wish to commit with the *+* button
3. Add a message like `commit tag : commit description `
> See the commit message standards bellow
4. Press Commit

## Git Commit Message Standards 

A git commit message should be of the form `commit tag (tag detail) : commit description `

### Commit Tags 
- `core` - A new feature or capability added to the codebase.
> Example: `core(player): Added flight controls` 
- `fix` - A bug fix or error resolution.
> Example: `fix(ui): Resolve status bar scaling`
- `docs` - Documentation-only changes (e.g., README updates, comments).
> Example: `docs`: updated readme
- `asset` - Adding media like models, images, audio
> Example: `asset(models): Added models to be launched`



