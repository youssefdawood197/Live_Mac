namespace Live.App.Views;

using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using Live.App.ViewModels;

public sealed partial class FlakeSettingsPage : Page
{
    public FlakeSettingsViewModel ViewModel { get; private set; } = null!;

    public FlakeSettingsPage()
    {
        InitializeComponent();
    }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        if (e.Parameter is FlakeSettingsViewModel vm)
        {
            ViewModel = vm;
        }
    }
}
