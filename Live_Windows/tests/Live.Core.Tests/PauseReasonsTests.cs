namespace Live.Core.Tests;

using Live.Core.Power;
using Xunit;

public class PauseReasonsTests
{
    [Fact]
    public void BitmaskRawValues_MatchExactPowersOfTwo()
    {
        Assert.Equal(0, (int)PauseReasons.None);
        Assert.Equal(1, (int)PauseReasons.UserPaused);
        Assert.Equal(2, (int)PauseReasons.FullscreenApp);
        Assert.Equal(4, (int)PauseReasons.DisplaySleeping);
        Assert.Equal(8, (int)PauseReasons.ScreenLocked);
        Assert.Equal(16, (int)PauseReasons.BatterySaver);
        Assert.Equal(31, (int)PauseReasons.All);
    }

    [Fact]
    public void AdditiveBitmaskTransitions_PreserveIndependentStates()
    {
        PauseReasons state = PauseReasons.None;
        Assert.Equal(0, (int)state);

        // Add fullscreen occlusion
        state |= PauseReasons.FullscreenApp;
        Assert.True(state.HasFlag(PauseReasons.FullscreenApp));
        Assert.False(state.HasFlag(PauseReasons.DisplaySleeping));

        // Add display sleeping
        state |= PauseReasons.DisplaySleeping;
        Assert.True(state.HasFlag(PauseReasons.FullscreenApp));
        Assert.True(state.HasFlag(PauseReasons.DisplaySleeping));
        Assert.Equal(6, (int)state);

        // Remove fullscreen occlusion
        state &= ~PauseReasons.FullscreenApp;
        Assert.False(state.HasFlag(PauseReasons.FullscreenApp));
        Assert.True(state.HasFlag(PauseReasons.DisplaySleeping));
        Assert.Equal(4, (int)state);

        // Remove display sleeping -> Back to none
        state &= ~PauseReasons.DisplaySleeping;
        Assert.Equal(PauseReasons.None, state);
    }

    [Fact]
    public void FormatDescription_FormatsActiveReasons()
    {
        Assert.Equal("none", PauseReasons.None.FormatDescription());
        Assert.Equal("userPaused", PauseReasons.UserPaused.FormatDescription());

        var multi = PauseReasons.FullscreenApp | PauseReasons.BatterySaver;
        string desc = multi.FormatDescription();
        Assert.Contains("fullscreenApp", desc);
        Assert.Contains("batterySaver", desc);
    }
}
