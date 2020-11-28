Most of the work with ProfileService is setting up your data loading code. Afterwards, data is read and written directly to the `Profile.Data` table without the nescessety to use any ProfileService method calls - you set up your own read / write functions, wrappers, classes with profiles as components, etc!

The code below is a basic profile loader implementation for ProfileService:

!!! note
	Unlike most custom DataStore modules where you would listen for `Players.PlayerRemoving` to clean up,
	ProfileService may release (destroy) the profile before the player leaves the server - this has to be
	handled by using `Profile:ListenToRelease(listener_function)` - any amount of functions can be added!