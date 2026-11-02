using System;
using System.Windows.Forms;
namespace CuteTerm;
internal static class Program
{
    [STAThread]
    static void Main()
    {
        ApplicationConfiguration.Initialize();
        Application.Run(new TerminalForm());
    }
}