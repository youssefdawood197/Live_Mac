namespace Live.App.Views;

using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using Live.App.ViewModels;

public sealed partial class GalleryPage : Page
{
    public MainViewModel ViewModel { get; private set; } = null!;

    public GalleryPage()
    {
        InitializeComponent();
    }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        if (e.Parameter is MainViewModel vm)
        {
            ViewModel = vm;
        }
    }

    private void AddWallpaper_Click(object sender, RoutedEventArgs e)
    {
        // Add wallpaper dialog
    }

    private void TogglePlay_Click(object sender, RoutedEventArgs e)
    {
        ViewModel?.TogglePause();
    }

    private void ToggleMute_Click(object sender, RoutedEventArgs e)
    {
        ViewModel?.ToggleMute();
    }
}
