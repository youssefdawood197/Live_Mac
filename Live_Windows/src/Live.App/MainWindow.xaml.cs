namespace Live.App;

using System;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Live.App.ViewModels;
using Live.App.Views;

public sealed partial class MainWindow : Window
{
    public MainViewModel ViewModel { get; }

    public MainWindow()
    {
        InitializeComponent();
        ViewModel = new MainViewModel(App.State);

        NavView.SelectedItem = NavView.MenuItems[0];
        ContentFrame.Navigate(typeof(GalleryPage), ViewModel);
    }

    private void NavView_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.IsSettingsSelected)
        {
            ContentFrame.Navigate(typeof(SettingsPage), ViewModel);
            return;
        }

        if (args.SelectedItem is NavigationViewItem item)
        {
            string tag = item.Tag?.ToString() ?? string.Empty;
            switch (tag)
            {
                case "library":
                    ContentFrame.Navigate(typeof(GalleryPage), ViewModel);
                    break;
                case "flake":
                    ContentFrame.Navigate(typeof(FlakeSettingsPage), new FlakeSettingsViewModel(App.State));
                    break;
                case "settings":
                    ContentFrame.Navigate(typeof(SettingsPage), ViewModel);
                    break;
            }
        }
    }
}
