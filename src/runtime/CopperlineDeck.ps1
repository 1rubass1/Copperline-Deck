param([switch]$SelfTest)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$ctl = Join-Path $root '.control'
$logPath = Join-Path $root 'logs\console-manager.log'
$iconPath = Join-Path $root 'assets\copperline-deck.ico'
$windowMutex = $null
$activateEvent = $null
if (-not $SelfTest) {
    $sha = [Security.Cryptography.SHA256]::Create()
    $keySeed = $PSScriptRoot.ToLowerInvariant()+'|gpu-lab'
    $key = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($keySeed))).Replace('-','')
    $sha.Dispose()
    $activateEvent = New-Object Threading.EventWaitHandle($false,[Threading.EventResetMode]::AutoReset,('Local\CreateServerActivate-'+$key))
    $windowMutex = New-Object Threading.Mutex($false,('Local\CreateServerWindow-'+$key))
    try { $ownsWindow = $windowMutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsWindow = $true }
    if (-not $ownsWindow) {
        [void]$activateEvent.Set()
        $activateEvent.Dispose()
        $windowMutex.Dispose()
        exit 0
    }
}
Add-Type -Path (Join-Path $PSScriptRoot 'taskbar-identity.cs')
$taskbarAppId=[CopperlineTaskbarIdentity]::SetProcess('CopperlineDeck.ServerConsole')
if($taskbarAppId -ne 'CopperlineDeck.ServerConsole'){throw 'Taskbar identity failed'}
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$webView2Root=Join-Path $PSScriptRoot 'webview2'
$webUiRoot=Join-Path $PSScriptRoot 'webui'
$env:PATH=$webView2Root+';'+$env:PATH
Add-Type -Path (Join-Path $webView2Root 'Microsoft.Web.WebView2.Core.dll')
Add-Type -Path (Join-Path $webView2Root 'Microsoft.Web.WebView2.WinForms.dll')
Add-Type -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public static class RdcNativeWindow {
    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    private delegate int SetPreferredAppModeDelegate(int mode);
    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    private delegate bool AllowDarkModeForWindowDelegate(IntPtr hwnd, bool allow);

    private static SetPreferredAppModeDelegate setPreferred;
    private static AllowDarkModeForWindowDelegate allowWindow;

    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)]
    private static extern IntPtr LoadLibrary(string fileName);
    [DllImport("kernel32.dll")]
    private static extern IntPtr GetProcAddress(IntPtr module, IntPtr ordinal);
    [DllImport("uxtheme.dll", CharSet=CharSet.Unicode)]
    private static extern int SetWindowTheme(IntPtr hwnd, string appName, string idList);
    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT {
        public int Left, Top, Right, Bottom;
    }

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")]
    private static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")]
    private static extern IntPtr GetWindow(IntPtr hWnd, uint uCmd);
    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("dwmapi.dll")]
    private static extern int DwmGetWindowAttribute(IntPtr hwnd, int attr, out int value, int size);

    private const uint GW_HWNDPREV = 3;
    private const int DWMWA_CLOAKED = 14;

    private static bool IsCloaked(IntPtr hwnd) {
        try {
            int value;
            return DwmGetWindowAttribute(hwnd,DWMWA_CLOAKED,out value,sizeof(int))==0 && value!=0;
        } catch { return false; }
    }

    public static bool IsFullyOccluded(IntPtr hwnd) {
        if(hwnd==IntPtr.Zero || !IsWindowVisible(hwnd) || IsIconic(hwnd)) return true;
        RECT rr;
        if(!GetWindowRect(hwnd,out rr)) return false;
        Rectangle target=Rectangle.FromLTRB(rr.Left,rr.Top,rr.Right,rr.Bottom);
        if(target.Width<=0 || target.Height<=0) return true;

        using(Region remaining=new Region(target))
        using(Matrix matrix=new Matrix()) {
            IntPtr above=GetWindow(hwnd,GW_HWNDPREV);
            int guard=0;
            while(above!=IntPtr.Zero && guard++<512) {
                if(IsWindowVisible(above) && !IsIconic(above) && !IsCloaked(above)) {
                    RECT ar;
                    if(GetWindowRect(above,out ar)) {
                        Rectangle cover=Rectangle.Intersect(
                            target,
                            Rectangle.FromLTRB(ar.Left,ar.Top,ar.Right,ar.Bottom)
                        );
                        if(cover.Width>0 && cover.Height>0) {
                            remaining.Exclude(cover);
                            if(remaining.GetRegionScans(matrix).Length==0) return true;
                        }
                    }
                }
                above=GetWindow(above,GW_HWNDPREV);
            }
            return remaining.GetRegionScans(matrix).Length==0;
        }
    }

    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(
        IntPtr hwnd,
        int dwAttribute,
        ref int pvAttribute,
        int cbAttribute
    );

    public static bool InitDarkAppMode() {
        try {
            IntPtr ux=LoadLibrary("uxtheme.dll");
            if(ux==IntPtr.Zero) return false;
            IntPtr p135=GetProcAddress(ux,new IntPtr(135));
            IntPtr p133=GetProcAddress(ux,new IntPtr(133));
            if(p135==IntPtr.Zero || p133==IntPtr.Zero) return false;
            setPreferred=(SetPreferredAppModeDelegate)Marshal.GetDelegateForFunctionPointer(p135,typeof(SetPreferredAppModeDelegate));
            allowWindow=(AllowDarkModeForWindowDelegate)Marshal.GetDelegateForFunctionPointer(p133,typeof(AllowDarkModeForWindowDelegate));
            setPreferred(2);
            return true;
        } catch { return false; }
    }

    public static void ApplyDarkScrollBars(IntPtr hwnd) {
        try {
            if(allowWindow!=null) allowWindow(hwnd,true);
            SetWindowTheme(hwnd,"DarkMode_Explorer","ScrollBar");
            SendMessage(hwnd,0x031A,IntPtr.Zero,IntPtr.Zero);
        } catch {}
    }
}

public class RdcMenuColorTable : ProfessionalColorTable {
    private readonly Color accent = Color.FromArgb(191,118,67);
    private readonly Color accentSoft = Color.FromArgb(166,98,55);

    public RdcMenuColorTable() {
        UseSystemColors = false;
    }

    public override Color ImageMarginGradientBegin { get { return accent; } }
    public override Color ImageMarginGradientMiddle { get { return accent; } }
    public override Color ImageMarginGradientEnd { get { return accent; } }

    public override Color CheckBackground { get { return accent; } }
    public override Color CheckPressedBackground { get { return accentSoft; } }
    public override Color CheckSelectedBackground { get { return accent; } }

    public override Color MenuItemSelected { get { return Color.FromArgb(77,58,47); } }
    public override Color MenuItemBorder { get { return Color.FromArgb(207,132,75); } }
    public override Color MenuItemPressedGradientBegin { get { return Color.FromArgb(77,58,47); } }
    public override Color MenuItemPressedGradientMiddle { get { return Color.FromArgb(77,58,47); } }
    public override Color MenuItemPressedGradientEnd { get { return Color.FromArgb(77,58,47); } }
}

public class RdcCircleButton : Control {
    private bool hovered;
    private bool pressed;

    public RdcCircleButton() {
        SetStyle(ControlStyles.UserPaint |
                 ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.ResizeRedraw |
                 ControlStyles.SupportsTransparentBackColor, true);
        BackColor = Color.Transparent;
        ForeColor = Color.FromArgb(248,248,248);
        Font = new Font("Segoe UI", 11f, FontStyle.Bold);
        Cursor = Cursors.Hand;
        TabStop = false;
        Size = new Size(36,36);
    }

    protected override void OnMouseEnter(EventArgs e) {
        hovered = true; Invalidate(); base.OnMouseEnter(e);
    }
    protected override void OnMouseLeave(EventArgs e) {
        hovered = false; pressed = false; Invalidate(); base.OnMouseLeave(e);
    }
    protected override void OnMouseDown(MouseEventArgs e) {
        if (e.Button == MouseButtons.Left) { pressed = true; Invalidate(); }
        base.OnMouseDown(e);
    }
    protected override void OnMouseUp(MouseEventArgs e) {
        pressed = false; Invalidate(); base.OnMouseUp(e);
    }
    protected override void OnPaint(PaintEventArgs e) {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
        Color fill = pressed ? Color.FromArgb(166,98,55)
                   : hovered ? Color.FromArgb(207,132,75)
                   : Color.FromArgb(191,118,67);
        Color edge = pressed ? Color.FromArgb(139,81,45)
                   : hovered ? Color.FromArgb(224,151,91)
                   : Color.FromArgb(163,96,52);
        RectangleF r = new RectangleF(1.5f,1.5f,Width-3f,Height-3f);
        using (SolidBrush b = new SolidBrush(fill)) e.Graphics.FillEllipse(b,r);
        using (Pen p = new Pen(edge,1f)) e.Graphics.DrawEllipse(p,r);
        TextRenderer.DrawText(
            e.Graphics, Text, Font, ClientRectangle, ForeColor,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter |
            TextFormatFlags.SingleLine | TextFormatFlags.NoPadding);
    }
}

public class RdcRoundedButton : Control {
    private bool hovered;
    private bool pressed;
    private string glyph = String.Empty;

    public string Glyph {
        get { return glyph; }
        set { glyph = value ?? String.Empty; Invalidate(); }
    }

    public RdcRoundedButton() {
        SetStyle(ControlStyles.UserPaint |
                 ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.ResizeRedraw |
                 ControlStyles.SupportsTransparentBackColor, true);
        BackColor = Color.Transparent;
        ForeColor = Color.FromArgb(238,238,238);
        Font = new Font("Segoe UI Semibold", 10f, FontStyle.Regular);
        Cursor = Cursors.Hand;
        TabStop = false;
    }

    protected override void OnMouseEnter(EventArgs e) {
        hovered = true; Invalidate(); base.OnMouseEnter(e);
    }
    protected override void OnMouseLeave(EventArgs e) {
        hovered = false; pressed = false; Invalidate(); base.OnMouseLeave(e);
    }
    protected override void OnMouseDown(MouseEventArgs e) {
        if (e.Button == MouseButtons.Left) { pressed = true; Invalidate(); }
        base.OnMouseDown(e);
    }
    protected override void OnMouseUp(MouseEventArgs e) {
        pressed = false; Invalidate(); base.OnMouseUp(e);
    }
    private GraphicsPath Rounded(RectangleF r, float radius) {
        GraphicsPath p = new GraphicsPath();
        float d = radius * 2f;
        p.AddArc(r.Left,r.Top,d,d,180,90);
        p.AddArc(r.Right-d,r.Top,d,d,270,90);
        p.AddArc(r.Right-d,r.Bottom-d,d,d,0,90);
        p.AddArc(r.Left,r.Bottom-d,d,d,90,90);
        p.CloseFigure();
        return p;
    }

    private void DrawGlyph(Graphics g, Color color) {
        if (String.IsNullOrEmpty(glyph)) return;
        float cx = 16f;
        float cy = Height / 2f;
        using (Pen p = new Pen(color,1.6f)) {
            p.StartCap = LineCap.Round;
            p.EndCap = LineCap.Round;
            if (glyph == "play") {
                using (SolidBrush b = new SolidBrush(color)) {
                    PointF[] pts = {
                        new PointF(cx-3.5f,cy-6f),
                        new PointF(cx+5.5f,cy),
                        new PointF(cx-3.5f,cy+6f)
                    };
                    g.FillPolygon(b,pts);
                }
            } else if (glyph == "stop") {
                using (SolidBrush b = new SolidBrush(color))
                    g.FillRectangle(b,cx-5f,cy-5f,10f,10f);
            } else if (glyph == "restart") {
                g.DrawArc(p,cx-6f,cy-6f,12f,12f,-35f,285f);
                using (SolidBrush b = new SolidBrush(color)) {
                    PointF[] pts = {
                        new PointF(cx+4.2f,cy-7.2f),
                        new PointF(cx+7.2f,cy-1.2f),
                        new PointF(cx+0.8f,cy-2.5f)
                    };
                    g.FillPolygon(b,pts);
                }
            } else if (glyph == "folder") {
                g.DrawRectangle(p,cx-7f,cy-4f,14f,9f);
                g.DrawLine(p,cx-6f,cy-4f,cx-3f,cy-7f);
                g.DrawLine(p,cx-3f,cy-7f,cx+1f,cy-7f);
                g.DrawLine(p,cx+1f,cy-7f,cx+3f,cy-4f);
            } else if (glyph == "send") {
                PointF[] pts = {
                    new PointF(cx-7f,cy-5f),
                    new PointF(cx+7f,cy),
                    new PointF(cx-7f,cy+5f),
                    new PointF(cx-3f,cy),
                };
                g.DrawPolygon(p,pts);
                g.DrawLine(p,cx-3f,cy,cx+5.5f,cy);
            }
        }
    }

    protected override void OnPaint(PaintEventArgs e) {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
        Color fill = !Enabled ? Color.FromArgb(40,43,47)
                   : pressed ? Color.FromArgb(42,46,51)
                   : hovered ? Color.FromArgb(61,66,72)
                   : Color.FromArgb(49,53,59);
        Color edge = !Enabled ? Color.FromArgb(78,82,87)
                   : pressed ? Color.FromArgb(139,81,45)
                   : hovered ? Color.FromArgb(207,132,75)
                   : Color.FromArgb(191,118,67);
        Color textColor = !Enabled ? Color.FromArgb(128,132,138) : ForeColor;
        Color glyphColor = !Enabled ? Color.FromArgb(128,132,138)
                         : pressed ? Color.FromArgb(166,98,55)
                         : hovered ? Color.FromArgb(224,151,91)
                         : Color.FromArgb(191,118,67);
        RectangleF r = new RectangleF(1f,1f,Width-2f,Height-2f);
        using (GraphicsPath p = Rounded(r,6f))
        using (SolidBrush b = new SolidBrush(fill))
        using (Pen pen = new Pen(edge,1f)) {
            e.Graphics.FillPath(b,p);
            e.Graphics.DrawPath(pen,p);
        }
        DrawGlyph(e.Graphics,glyphColor);
        Rectangle textRect = String.IsNullOrEmpty(glyph)
            ? ClientRectangle
            : new Rectangle(25,0,Math.Max(1,Width-28),Height);
        TextRenderer.DrawText(
            e.Graphics, Text, Font, textRect, textColor,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter |
            TextFormatFlags.SingleLine | TextFormatFlags.NoPadding);
    }
}

public class RdcStatusIndicator : Control {
    private Color indicatorColor = Color.Gray;
    public Color IndicatorColor {
        get { return indicatorColor; }
        set { indicatorColor = value; Invalidate(); }
    }

    public RdcStatusIndicator() {
        SetStyle(ControlStyles.UserPaint |
                 ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.ResizeRedraw |
                 ControlStyles.SupportsTransparentBackColor, true);
        BackColor = Color.Transparent;
        TabStop = false;
    }

    protected override void OnPaint(PaintEventArgs e) {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        int diameter = 18;
        int x = (Width - diameter) / 2;
        int y = (Height - diameter) / 2;
        using (SolidBrush b = new SolidBrush(indicatorColor))
            e.Graphics.FillEllipse(b, x, y, diameter, diameter);
    }
}

public class RdcLogBox : RichTextBox {
    private const int WM_HSCROLL = 0x0114;
    private const int WM_VSCROLL = 0x0115;
    private const int WM_MOUSEWHEEL = 0x020A;
    private const int WM_MOUSEHWHEEL = 0x020E;
    private const int WM_SETREDRAW = 0x000B;
    private const int MK_CONTROL = 0x0008;

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct SCROLLINFO {
        public uint cbSize;
        public uint fMask;
        public int nMin;
        public int nMax;
        public uint nPage;
        public int nPos;
        public int nTrackPos;
    }

    [DllImport("user32.dll")]
    private static extern bool GetScrollInfo(IntPtr hwnd, int nBar, ref SCROLLINFO info);

    private const uint SIF_ALL = 0x17;
    private const int SB_VERT = 1;

    public event EventHandler ScrollActivity;

    [StructLayout(LayoutKind.Sequential)]
    private struct VIEWPOINT { public int X; public int Y; }

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr hWnd, uint msg, IntPtr wParam, ref VIEWPOINT lParam);

    private const uint EM_GETSCROLLPOS = 0x04DD;
    private const uint EM_SETSCROLLPOS = 0x04DE;
    public RdcLogBox() {
        ZoomFactor = 1.0f;
        HideSelection = true;
    }

    public static string ReadChunk(TextReader reader, int maxChars) {
        if (reader == null || maxChars <= 0) return String.Empty;
        char[] buffer = new char[maxChars];
        int count = reader.Read(buffer, 0, buffer.Length);
        return count > 0 ? new String(buffer, 0, count) : String.Empty;
    }

    public Point GetViewPosition() {
        VIEWPOINT pt = new VIEWPOINT();
        SendMessage(Handle,EM_GETSCROLLPOS,IntPtr.Zero,ref pt);
        return new Point(pt.X,pt.Y);
    }

    public bool IsAtVerticalEnd() {
        if (!IsHandleCreated) return true;
        SCROLLINFO si = new SCROLLINFO();
        si.cbSize = (uint)Marshal.SizeOf(typeof(SCROLLINFO));
        si.fMask = SIF_ALL;
        if (!GetScrollInfo(Handle,SB_VERT,ref si)) return true;
        int maxPos = Math.Max(si.nMin,si.nMax-(int)si.nPage+1);
        return (maxPos-si.nPos) <= 3;
    }

    public void SetViewPosition(int x,int y) {
        VIEWPOINT pt = new VIEWPOINT();
        pt.X = Math.Max(0,x);
        pt.Y = Math.Max(0,y);
        SendMessage(Handle,EM_SETSCROLLPOS,IntPtr.Zero,ref pt);
    }

    public void RemoveLeadingText(int count) {
        if (count <= 0 || TextLength <= 0) return;

        count = Math.Min(count, TextLength);
        bool wasReadOnly = ReadOnly;
        int oldStart = SelectionStart;
        int oldLength = SelectionLength;
        bool hadUserSelection = Focused && oldLength > 0;

        SendMessage(Handle, WM_SETREDRAW, IntPtr.Zero, IntPtr.Zero);
        try {
            if (wasReadOnly) ReadOnly = false;
            Select(0, count);
            SelectedText = String.Empty;

            if (hadUserSelection) {
                int newStart = Math.Max(0, oldStart - count);
                int newLength = Math.Min(oldLength, Math.Max(0, TextLength - newStart));
                Select(newStart, newLength);
            } else {
                Select(TextLength, 0);
            }
        }
        finally {
            if (wasReadOnly) ReadOnly = true;
            SendMessage(Handle, WM_SETREDRAW, new IntPtr(1), IntPtr.Zero);
            Invalidate();
        }
    }

    protected override void WndProc(ref Message m) {
        bool scrollMessage =
            m.Msg == WM_HSCROLL ||
            m.Msg == WM_VSCROLL ||
            m.Msg == WM_MOUSEWHEEL ||
            m.Msg == WM_MOUSEHWHEEL;

        if (m.Msg == WM_MOUSEWHEEL || m.Msg == WM_MOUSEHWHEEL) {
            long raw = m.WParam.ToInt64();
            int keyState = (int)(raw & 0xFFFF);

            if ((keyState & MK_CONTROL) != 0) {
                raw &= ~((long)MK_CONTROL);
                m.WParam = new IntPtr(raw);
            }
        }

        base.WndProc(ref m);
        if (scrollMessage) {
            if (ScrollActivity != null && IsHandleCreated) {
                try {
                    BeginInvoke((MethodInvoker)delegate {
                        if (!IsDisposed && ScrollActivity != null)
                            ScrollActivity(this, EventArgs.Empty);
                    });
                } catch { }
            }
        }
    }

    protected override void OnKeyDown(KeyEventArgs e) {
        if (e.Control &&
            (e.KeyCode == Keys.Add ||
             e.KeyCode == Keys.Subtract ||
             e.KeyCode == Keys.Oemplus ||
             e.KeyCode == Keys.OemMinus ||
             e.KeyCode == Keys.D0 ||
             e.KeyCode == Keys.NumPad0)) {
            e.SuppressKeyPress = true;
            e.Handled = true;
            return;
        }
        base.OnKeyDown(e);
    }

    protected override void OnKeyPress(KeyPressEventArgs e) {
        if (ReadOnly && e.KeyChar != (char)3) {
            e.Handled = true;
            return;
        }
        base.OnKeyPress(e);
    }
}
public class RdcScrollCorner : Control {
    private const uint WM_NCLBUTTONDOWN = 0x00A1;
    private const int HTBOTTOMRIGHT = 17;

    [DllImport("user32.dll")]
    private static extern bool ReleaseCapture();
    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    public RdcScrollCorner() {
        SetStyle(ControlStyles.UserPaint |
                 ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.ResizeRedraw, true);
        Cursor = Cursors.SizeNWSE;
    }

    protected override void OnPaint(PaintEventArgs e) {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.Clear(Color.FromArgb(50,52,56));
        using (Pen p = new Pen(Color.FromArgb(191,118,67),1.4f)) {
            e.Graphics.DrawLine(p,10,15,15,10);
            e.Graphics.DrawLine(p,6,15,15,6);
            e.Graphics.DrawLine(p,2,15,15,2);
        }
    }

    protected override void OnMouseDown(MouseEventArgs e) {
        if (e.Button == MouseButtons.Left) {
            Form f = FindForm();
            if (f != null) {
                ReleaseCapture();
                SendMessage(f.Handle, WM_NCLBUTTONDOWN, new IntPtr(HTBOTTOMRIGHT), IntPtr.Zero);
                return;
            }
        }
        base.OnMouseDown(e);
    }
}

public class RdcOverlayScrollBar : Control {
    [StructLayout(LayoutKind.Sequential)]
    private struct SCROLLINFO {
        public uint cbSize;
        public uint fMask;
        public int nMin;
        public int nMax;
        public uint nPage;
        public int nPos;
        public int nTrackPos;
    }

    [DllImport("user32.dll")]
    private static extern bool GetScrollInfo(IntPtr hwnd, int nBar, ref SCROLLINFO info);
    [StructLayout(LayoutKind.Sequential)]
    private struct POINT {
        public int X;
        public int Y;
    }

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr hwnd, uint msg, IntPtr wParam, ref POINT lParam);

    private const uint EM_GETSCROLLPOS = 0x04DD;
    private const uint EM_SETSCROLLPOS = 0x04DE;
    private const uint SIF_ALL = 0x17;
    private const int SB_HORZ = 0;
    private const int SB_VERT = 1;
    private const uint WM_HSCROLL = 0x0114;
    private const uint WM_VSCROLL = 0x0115;
    private const int SB_LINEUP = 0;
    private const int SB_LINEDOWN = 1;
    private const int SB_PAGEUP = 2;
    private const int SB_PAGEDOWN = 3;
    private const int SB_THUMBPOSITION = 4;
    private const int SB_THUMBTRACK = 5;
    private const int SB_ENDSCROLL = 8;

    private bool dragging;
    private bool hoverThumb;
    private int dragOffset;
    private int dragVisualOffset = -1;
    private int dragLogicalPos = -1;
    public Control Target { get; set; }
    public bool Vertical { get; set; }
    public bool IsDragging { get { return dragging; } }

    public bool IsAtEnd {
        get {
            SCROLLINFO si = ReadInfo();
            int maxPos = Math.Max(si.nMin, si.nMax - (int)si.nPage + 1);
            return (maxPos - si.nPos) <= 3;
        }
    }

    public void ScrollToEnd() {
        if (Target == null || !Target.IsHandleCreated || !Vertical) return;
        SendMessage(Target.Handle, WM_VSCROLL, new IntPtr(7), IntPtr.Zero);
        Invalidate();
    }

    public RdcOverlayScrollBar() {
        SetStyle(ControlStyles.UserPaint |
                 ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.ResizeRedraw, true);
        Cursor = Cursors.Default;
    }

    private SCROLLINFO ReadInfo() {
        SCROLLINFO si = new SCROLLINFO();
        si.cbSize = (uint)Marshal.SizeOf(typeof(SCROLLINFO));
        si.fMask = SIF_ALL;
        if (Target != null && Target.IsHandleCreated)
            GetScrollInfo(Target.Handle, Vertical ? SB_VERT : SB_HORZ, ref si);
        return si;
    }

    private void Geometry(out Rectangle dec, out Rectangle inc, out Rectangle track, out Rectangle thumb) {
        int arrow = 16;
        if (Vertical) {
            dec = new Rectangle(0,0,Width,arrow);
            inc = new Rectangle(0,Math.Max(0,Height-arrow),Width,arrow);
            track = new Rectangle(2,arrow,Math.Max(1,Width-4),Math.Max(1,Height-arrow*2));
        } else {
            dec = new Rectangle(0,0,arrow,Height);
            inc = new Rectangle(Math.Max(0,Width-arrow),0,arrow,Height);
            track = new Rectangle(arrow,2,Math.Max(1,Width-arrow*2),Math.Max(1,Height-4));
        }

        SCROLLINFO si = ReadInfo();
        long range = Math.Max(1L, (long)si.nMax - si.nMin + 1L);
        long page = Math.Max(1L, (long)si.nPage);
        int trackLen = Vertical ? track.Height : track.Width;
        int thumbLen = Math.Max(26, (int)Math.Round(trackLen * Math.Min(1.0, (double)page / range)));
        thumbLen = Math.Min(trackLen, thumbLen);
        int maxPos = Math.Max(si.nMin, si.nMax - (int)si.nPage + 1);
        int posRange = Math.Max(1, maxPos - si.nMin);
        int travel = Math.Max(0, trackLen - thumbLen);
        int offset = travel == 0 ? 0 : (int)Math.Round((si.nPos - si.nMin) * (double)travel / posRange);
        if (dragging && dragVisualOffset >= 0)
            offset = Math.Max(0, Math.Min(travel, dragVisualOffset));

        if (Vertical)
            thumb = new Rectangle(track.X, track.Y + offset, track.Width, thumbLen);
        else
            thumb = new Rectangle(track.X + offset, track.Y, thumbLen, track.Height);
    }

    private GraphicsPath Rounded(Rectangle r, int radius) {
        GraphicsPath p = new GraphicsPath();
        int d = radius * 2;
        if (d <= 0 || r.Width <= d || r.Height <= d) { p.AddRectangle(r); return p; }
        p.AddArc(r.Left,r.Top,d,d,180,90);
        p.AddArc(r.Right-d,r.Top,d,d,270,90);
        p.AddArc(r.Right-d,r.Bottom-d,d,d,0,90);
        p.AddArc(r.Left,r.Bottom-d,d,d,90,90);
        p.CloseFigure();
        return p;
    }

    protected override void OnPaint(PaintEventArgs e) {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.Clear(Color.FromArgb(45,47,51));
        Rectangle dec,inc,track,thumb;
        Geometry(out dec,out inc,out track,out thumb);

        using (GraphicsPath tp = Rounded(track, Math.Min(6, Math.Min(track.Width,track.Height)/2)))
        using (SolidBrush tb = new SolidBrush(Color.FromArgb(50,52,56)))
            e.Graphics.FillPath(tb,tp);

        Color thumbColor = dragging
            ? Color.FromArgb(166,98,55)
            : hoverThumb
                ? Color.FromArgb(207,132,75)
                : Color.FromArgb(191,118,67);
        using (GraphicsPath hp = Rounded(thumb, Math.Min(7, Math.Min(thumb.Width,thumb.Height)/2)))
        using (SolidBrush hb = new SolidBrush(thumbColor))
            e.Graphics.FillPath(hb,hp);

        using (SolidBrush ab = new SolidBrush(Color.FromArgb(112,115,120))) {
            if (Vertical) {
                Point[] up = { new Point(Width/2,5), new Point(Width/2-4,10), new Point(Width/2+4,10) };
                Point[] dn = { new Point(Width/2,Height-5), new Point(Width/2-4,Height-10), new Point(Width/2+4,Height-10) };
                e.Graphics.FillPolygon(ab,up); e.Graphics.FillPolygon(ab,dn);
            } else {
                Point[] lt = { new Point(5,Height/2), new Point(10,Height/2-4), new Point(10,Height/2+4) };
                Point[] rt = { new Point(Width-5,Height/2), new Point(Width-10,Height/2-4), new Point(Width-10,Height/2+4) };
                e.Graphics.FillPolygon(ab,lt); e.Graphics.FillPolygon(ab,rt);
            }
        }
    }

    private void SetHorizontalPosition(int pos) {
        if (Target == null || !Target.IsHandleCreated) return;
        POINT pt = new POINT();
        SendMessage(Target.Handle, EM_GETSCROLLPOS, IntPtr.Zero, ref pt);
        pt.X = Math.Max(0,pos);
        SendMessage(Target.Handle, EM_SETSCROLLPOS, IntPtr.Zero, ref pt);
        Invalidate();
    }

    private void SendScroll(int code, int pos) {
        if (Target == null || !Target.IsHandleCreated) return;
        if (!Vertical && (code == SB_THUMBTRACK || code == SB_THUMBPOSITION)) {
            SetHorizontalPosition(pos);
            return;
        }
        int packed = (code & 0xFFFF) | ((pos & 0xFFFF) << 16);
        SendMessage(Target.Handle, Vertical ? WM_VSCROLL : WM_HSCROLL, new IntPtr(packed), IntPtr.Zero);
        Invalidate();
    }

    protected override void OnMouseDown(MouseEventArgs e) {
        Rectangle dec,inc,track,thumb; Geometry(out dec,out inc,out track,out thumb);
        Point p=e.Location;
        if (dec.Contains(p)) SendScroll(SB_LINEUP,0);
        else if (inc.Contains(p)) SendScroll(SB_LINEDOWN,0);
        else if (thumb.Contains(p)) {
            dragging=true;
            dragVisualOffset = Vertical ? (thumb.Y-track.Y) : (thumb.X-track.X);
            dragOffset=(Vertical ? p.Y-thumb.Y : p.X-thumb.X);
            Capture=true;
        } else if ((Vertical ? p.Y : p.X) < (Vertical ? thumb.Y : thumb.X))
            SendScroll(SB_PAGEUP,0);
        else
            SendScroll(SB_PAGEDOWN,0);
        base.OnMouseDown(e);
    }

    protected override void OnMouseMove(MouseEventArgs e) {
        Rectangle dec,inc,track,thumb; Geometry(out dec,out inc,out track,out thumb);
        hoverThumb=thumb.Contains(e.Location);
        if (dragging) {
            SCROLLINFO si=ReadInfo();
            int trackStart=Vertical ? track.Y : track.X;
            int trackLen=Vertical ? track.Height : track.Width;
            int thumbLen=Vertical ? thumb.Height : thumb.Width;
            int travel=Math.Max(1,trackLen-thumbLen);
            int raw=(Vertical ? e.Y : e.X)-dragOffset-trackStart;
            raw=Math.Max(0,Math.Min(travel,raw));
            dragVisualOffset = raw;
            int maxPos=Math.Max(si.nMin,si.nMax-(int)si.nPage+1);
            int pos=si.nMin+(int)Math.Round(raw*(double)Math.Max(1,maxPos-si.nMin)/travel);
            dragLogicalPos = pos;
            SendScroll(SB_THUMBTRACK,pos);
        }
        Invalidate();
        base.OnMouseMove(e);
    }

    protected override void OnMouseLeave(EventArgs e) {
        if (!dragging) { hoverThumb=false; Invalidate(); }
        base.OnMouseLeave(e);
    }

    protected override void OnMouseUp(MouseEventArgs e) {
        if (dragging) {
            int finalPos = dragLogicalPos;
            dragging=false; Capture=false;
            dragVisualOffset = -1;
            dragLogicalPos = -1;
            if (!Vertical && finalPos >= 0) {
                SetHorizontalPosition(finalPos);
            } else {
                SCROLLINFO si=ReadInfo();
                SendScroll(SB_THUMBPOSITION,si.nPos);
                SendScroll(SB_ENDSCROLL,0);
            }
        }
        Invalidate();
        base.OnMouseUp(e);
    }
}
'@ -ReferencedAssemblies @('System.Drawing','System.Windows.Forms')
[void][RdcNativeWindow]::InitDarkAppMode()
[Windows.Forms.Application]::EnableVisualStyles()
$form = New-Object Windows.Forms.Form
$form.Text = 'Copperline Deck | Minecraft Server'
$baseWindowWidth=1120; $baseWindowHeight=760
$startupScreen=[Windows.Forms.Screen]::FromPoint([Windows.Forms.Cursor]::Position)
$startupWorkArea=$startupScreen.WorkingArea
$windowWidth=[Math]::Min($baseWindowWidth,$startupWorkArea.Width)
$windowHeight=[Math]::Min($baseWindowHeight,$startupWorkArea.Height)
$form.Size = New-Object Drawing.Size($windowWidth,$windowHeight)
$form.MinimumSize = New-Object Drawing.Size([Math]::Min(840,$windowWidth),[Math]::Min(560,$windowHeight))
$form.StartPosition = 'Manual'
$form.Location = New-Object Drawing.Point(
    ($startupWorkArea.Left+[Math]::Max(0,[int](($startupWorkArea.Width-$windowWidth)/2))),
    ($startupWorkArea.Top+[Math]::Max(0,[int](($startupWorkArea.Height-$windowHeight)/2)))
)
$form.BackColor = [Drawing.Color]::FromArgb(29,32,36)
$form.ForeColor = [Drawing.Color]::Gainsboro
$form.Font = New-Object Drawing.Font('Segoe UI',10)
if(Test-Path $iconPath){$form.Icon = New-Object Drawing.Icon($iconPath)}
$accentOrange = [Drawing.Color]::FromArgb(191,118,67)
$accentPurple = [Drawing.Color]::FromArgb(123,95,162)


$logReady = [Drawing.Color]::LightGreen
$logWarn = [Drawing.Color]::Khaki
$logError = [Drawing.Color]::LightCoral
$logPlayerJoin = [Drawing.Color]::PaleGreen
$logPlayerLeave = [Drawing.Color]::LightSteelBlue
$logSave = [Drawing.Color]::Plum
$logInfo = [Drawing.Color]::PaleTurquoise
$logCommand = [Drawing.Color]::Gold
$top = New-Object Windows.Forms.TableLayoutPanel
$top.Dock='Top'; $top.Height=78; $top.Padding=New-Object Windows.Forms.Padding(16,9,16,9)
$top.Add_Paint({
    param($sender,$e)
    $pen=New-Object Drawing.Pen([Drawing.Color]::FromArgb(123,95,162),1)
    try{$y=[Math]::Max(0,$sender.ClientSize.Height-1);$e.Graphics.DrawLine($pen,0,$y,$sender.ClientSize.Width,$y)}finally{$pen.Dispose()}
})
$top.ColumnCount=3; $top.RowCount=2
[void]$top.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,38)))
[void]$top.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
[void]$top.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,590)))
[void]$top.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,32)))
[void]$top.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))
$statusDot = New-Object RdcStatusIndicator
$statusDot.Dock='Fill'; $statusDot.IndicatorColor=[Drawing.Color]::Gray
$title = New-Object Windows.Forms.Label
$title.Dock='Fill'; $title.TextAlign='MiddleLeft'; $title.Font=New-Object Drawing.Font('Segoe UI',13,[Drawing.FontStyle]::Bold)
$detail = New-Object Windows.Forms.Label
$detail.Dock='Fill'; $detail.TextAlign='MiddleLeft'; $detail.ForeColor=[Drawing.Color]::Silver
function New-TopButton([string]$text,[int]$width){
    $b=New-Object RdcRoundedButton; $b.Text=$text; $b.Size=New-Object Drawing.Size($width,36)
    $b.Margin=New-Object Windows.Forms.Padding(8,0,0,0); return $b
}
$start = New-TopButton 'Запустить' 110; $start.Glyph='play'
$stop = New-TopButton 'Остановить' 120; $stop.Glyph='stop'
$restart = New-TopButton 'Перезапустить' 140; $restart.Glyph='restart'
$folder = New-TopButton 'Папка сервера' 140; $folder.Glyph='folder'
$helpButton = New-Object RdcCircleButton
$helpButton.Text='?'; $helpButton.Size=New-Object Drawing.Size(36,36); $helpButton.Margin=New-Object Windows.Forms.Padding(8,0,0,0)
$actions=New-Object Windows.Forms.FlowLayoutPanel
$actions.Dock='Fill'; $actions.FlowDirection='LeftToRight'; $actions.WrapContents=$false
$actions.Margin=New-Object Windows.Forms.Padding(0); $actions.Padding=New-Object Windows.Forms.Padding(0,12,0,12)
$actions.Controls.Add($start); $actions.Controls.Add($stop); $actions.Controls.Add($restart); $actions.Controls.Add($folder); $actions.Controls.Add($helpButton)
$top.Controls.Add($statusDot,0,0); $top.SetRowSpan($statusDot,2)
$top.Controls.Add($title,1,0); $top.Controls.Add($detail,1,1)
$top.Controls.Add($actions,2,0); $top.SetRowSpan($actions,2)
$tip=New-Object Windows.Forms.ToolTip
$tip.SetToolTip($start,'Запустить Minecraft-сервер')
$tip.SetToolTip($stop,'Сохранить мир и остановить сервер')
$tip.SetToolTip($restart,'Перезапустить сервер')
$tip.SetToolTip($folder,'Открыть папку сервера')
$tip.SetToolTip($helpButton,'Справка и журнал')
$bottom=New-Object Windows.Forms.TableLayoutPanel
$bottom.Dock='Bottom'; $bottom.Height=104; $bottom.Padding=New-Object Windows.Forms.Padding(12,6,12,6)
$bottom.Add_Paint({
    param($sender,$e)
    $pen=New-Object Drawing.Pen([Drawing.Color]::FromArgb(123,95,162),1)
    try{$e.Graphics.DrawLine($pen,0,0,$sender.ClientSize.Width,0)}finally{$pen.Dispose()}
})
$bottom.ColumnCount=1; $bottom.RowCount=3
[void]$bottom.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,26)))
[void]$bottom.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,40)))
[void]$bottom.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))
$service=New-Object Windows.Forms.TableLayoutPanel
$service.Dock='Fill'; $service.ColumnCount=1; $service.RowCount=1; $service.Margin=New-Object Windows.Forms.Padding(0)
[void]$service.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
$serviceInfo=New-Object Windows.Forms.FlowLayoutPanel
$serviceInfo.Dock='Fill'; $serviceInfo.FlowDirection='LeftToRight'; $serviceInfo.WrapContents=$false; $serviceInfo.Margin=New-Object Windows.Forms.Padding(0)
$pidLabel=New-Object Windows.Forms.Label; $pidLabel.AutoSize=$false; $pidLabel.Width=120; $pidLabel.TextAlign='MiddleLeft'; $pidLabel.ForeColor=[Drawing.Color]::Silver; $pidLabel.Margin=New-Object Windows.Forms.Padding(0,0,0,0)
$sep1=New-Object Windows.Forms.Label; $sep1.AutoSize=$true; $sep1.Text='|'; $sep1.ForeColor=$accentOrange; $sep1.Margin=New-Object Windows.Forms.Padding(6,2,6,0)
$ramLabel=New-Object Windows.Forms.Label; $ramLabel.AutoSize=$false; $ramLabel.Width=135; $ramLabel.TextAlign='MiddleLeft'; $ramLabel.ForeColor=[Drawing.Color]::Silver; $ramLabel.Margin=New-Object Windows.Forms.Padding(0,0,0,0)
$sep2=New-Object Windows.Forms.Label; $sep2.AutoSize=$true; $sep2.Text='|'; $sep2.ForeColor=$accentOrange; $sep2.Margin=New-Object Windows.Forms.Padding(6,2,6,0)
$uptimeLabel=New-Object Windows.Forms.Label; $uptimeLabel.AutoSize=$false; $uptimeLabel.Width=190; $uptimeLabel.TextAlign='MiddleLeft'; $uptimeLabel.ForeColor=[Drawing.Color]::Silver; $uptimeLabel.Margin=New-Object Windows.Forms.Padding(0,0,0,0)
$serviceInfo.Controls.Add($pidLabel); $serviceInfo.Controls.Add($sep1); $serviceInfo.Controls.Add($ramLabel); $serviceInfo.Controls.Add($sep2); $serviceInfo.Controls.Add($uptimeLabel)
$service.Controls.Add($serviceInfo,0,0)
$commandRow=New-Object Windows.Forms.TableLayoutPanel
$commandRow.Dock='Fill'; $commandRow.ColumnCount=2; $commandRow.RowCount=1; $commandRow.Margin=New-Object Windows.Forms.Padding(0)
[void]$commandRow.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
[void]$commandRow.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,122)))
$commandInput=New-Object Windows.Forms.TextBox
$commandInput.Dock='Fill'; $commandInput.Multiline=$true; $commandInput.AcceptsReturn=$false; $commandInput.WordWrap=$false
$commandInput.Font=New-Object Drawing.Font('Consolas',11); $commandInput.BackColor=[Drawing.Color]::FromArgb(45,47,51)
$commandInput.ForeColor=[Drawing.Color]::Gainsboro; $commandInput.BorderStyle='FixedSingle'; $commandInput.Margin=New-Object Windows.Forms.Padding(0,2,0,2)
$send=New-Object RdcRoundedButton
$send.Text='Отправить'; $send.Glyph='send'; $send.Dock='Fill'; $send.Margin=New-Object Windows.Forms.Padding(8,2,0,2)
$commandRow.Controls.Add($commandInput,0,0); $commandRow.Controls.Add($send,1,0)
$hint=New-Object Windows.Forms.Label
$hint.Text='Enter — отправить. Закрытие окна оставляет сервер работающим.'
$hint.Dock='Fill'; $hint.TextAlign='MiddleLeft'; $hint.ForeColor=[Drawing.Color]::Gray
$bottom.Controls.Add($service,0,0); $bottom.Controls.Add($commandRow,0,1); $bottom.Controls.Add($hint,0,2)
$log=New-Object RdcLogBox
$log.ReadOnly=$true; $log.BackColor=[Drawing.Color]::FromArgb(18,20,23); $log.ForeColor=[Drawing.Color]::Gainsboro
$log.Font=New-Object Drawing.Font('Consolas',10); $log.WordWrap=$true; $log.BorderStyle='None'
$log.ScrollBars=[Windows.Forms.RichTextBoxScrollBars]::Both; $log.DetectUrls=$true
$log.Visible=$false; $log.Size=New-Object Drawing.Size(1,1)
[void]$log.Handle

$webLog=New-Object Microsoft.Web.WebView2.WinForms.WebView2
$webLog.Dock='Fill'; $webLog.Margin=New-Object Windows.Forms.Padding(0)
$webLog.DefaultBackgroundColor=[Drawing.Color]::FromArgb(18,20,23)
$webCreation=New-Object Microsoft.Web.WebView2.WinForms.CoreWebView2CreationProperties
$webCreation.UserDataFolder=Join-Path $root '.webview2-data'
$webLog.CreationProperties=$webCreation

$form.Controls.Add($webLog); $form.Controls.Add($bottom); $form.Controls.Add($top)
$script:job=$null; $script:reader=$null; $script:lastFrameDark=$null
$script:readerSessionKey=$null; $script:smartFollow=$true
$script:hadActiveSession=$false; $script:sessionEndedShown=$false; $script:offlineViewShown=$false
$logCatchupThresholdBytes=262144
$logCatchupTailBytes=184320
$nl=[Environment]::NewLine
function Get-SystemDarkMode {
    try {
        $theme=Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -ErrorAction Stop
        return ([int]$theme.AppsUseLightTheme -eq 0)
    } catch { return $false }
}
function Apply-SystemFrameTheme {
    try {
        $dark=Get-SystemDarkMode
        if($script:lastFrameDark -ne $dark -and $form.Handle -ne [IntPtr]::Zero){
            [int]$value=if($dark){1}else{0}
            [void][RdcNativeWindow]::DwmSetWindowAttribute($form.Handle,20,[ref]$value,4)
            $script:lastFrameDark=$dark
        }
    } catch {}
}
function Set-State([string]$name,[string]$message,[Drawing.Color]$color){
    $statusDot.IndicatorColor=$color
    $title.Text='Copperline Deck | Minecraft Server  —  '+$name
    $detail.Text=$message
}
function Color-LogRegex([string]$pattern,[Drawing.Color]$color,[int]$from){
    if($log.TextLength -le $from){return}
    try {
        $segment=$log.Text.Substring($from)
        $opts=[Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [Text.RegularExpressions.RegexOptions]::Multiline
        foreach($m in [regex]::Matches($segment,$pattern,$opts)){
            $log.Select($from+$m.Index,$m.Length)
            $log.SelectionColor=$color
        }
    } catch {}
}
function Style-LogTail([int]$from){
    if($log.TextLength -le 0){return}
    $start=[Math]::Max(0,$from-384)
    $end=$log.TextLength
    try {
        $log.Select($start,$end-$start); $log.SelectionColor=$log.ForeColor
        Color-LogRegex '^=== .+ ===\s*$' $accentPurple $start
        Color-LogRegex '^> .+$' $logCommand $start
        Color-LogRegex '^.*Preparing spawn area:.*$' $accentOrange $start
        Color-LogRegex '^.*Done \([^)]+\)! For help, type "help".*$' $logReady $start
        Color-LogRegex '^.*(?:logged in with entity id|joined the game|Player \[[^\]]+\] joined\.).*$' $logPlayerJoin $start
        Color-LogRegex '^.*(?:left the game|lost connection:|disconnected\.).*$' $logPlayerLeave $start
        Color-LogRegex '^.*There are \d+ of a max of \d+ players online.*$' $logInfo $start
        Color-LogRegex '^.*(?:Stopping the server|Stopping server|Saving players|Saving worlds|All dimensions are saved).*$' $logSave $start
        Color-LogRegex '^.*\/WARN\]:.*$' $logWarn $start
        Color-LogRegex '^(?:Ошибка:|Не удалось|Тайм-аут).*$|^.*(?:\/ERROR\]|\/FATAL\]|Exception|Caused by:).*$' $logError $start
    } catch {}
}
$script:webReady=$false
$script:webInitStarted=$false
$script:webRenderer='not-ready'
$script:lastFxPaused=$null

function Send-WebLogMessage([string]$type,[string]$text=$null){
    if(-not $script:webReady -or -not $webLog.CoreWebView2){return}
    try {
        $payload=if($null -eq $text){@{type=$type}}else{@{type=$type;text=$text}}
        $json=$payload|ConvertTo-Json -Compress
        $webLog.CoreWebView2.PostWebMessageAsJson($json)
    } catch {}
}
function Sync-WebLogFull {
    if($script:webReady){Send-WebLogMessage 'set' $log.Text}
}
function Clear-LogView {
    $log.Clear()
    Send-WebLogMessage 'clear'
}
function Update-FxVisibility([bool]$force){
    try {
        $paused=(-not $form.Visible) -or ($form.WindowState -eq [Windows.Forms.FormWindowState]::Minimized)
        if(-not $paused -and $form.Handle -ne [IntPtr]::Zero){
            $paused=[RdcNativeWindow]::IsFullyOccluded($form.Handle)
        }
        if($force -or $script:lastFxPaused -ne $paused){
            $script:lastFxPaused=$paused
            Send-WebLogMessage 'fxPause' $(if($paused){'1'}else{'0'})
        }
    } catch {}
}
function Initialize-WebLog {
    if($script:webInitStarted){return}
    $script:webInitStarted=$true
    try {
        [void]$webLog.Handle
        $task=$webLog.EnsureCoreWebView2Async()
        while(-not $task.IsCompleted){
            [Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 10
        }
        if($task.IsFaulted){throw $task.Exception}

        $core=$webLog.CoreWebView2
        $core.Settings.AreDevToolsEnabled=$false
        $core.Settings.IsStatusBarEnabled=$false
        $core.Settings.IsZoomControlEnabled=$false
        $core.Settings.IsPinchZoomEnabled=$false
        $core.SetVirtualHostNameToFolderMapping(
            'create.local',
            $webUiRoot,
            [Microsoft.Web.WebView2.Core.CoreWebView2HostResourceAccessKind]::Allow
        )
        $core.add_WebMessageReceived({
            param($sender,$e)
            try {
                $msg=$e.WebMessageAsJson|ConvertFrom-Json
                if($msg.type -eq 'ready'){
                    $script:webRenderer=[string]$msg.renderer
                    $script:webReady=$true
                    $script:webFrameInfo='ready '+$msg.renderer+' '+$msg.canvasWidth+'x'+$msg.canvasHeight
                    Sync-WebLogFull
                    Update-FxVisibility $true
                } elseif($msg.type -eq 'frame'){
                    $script:webFrameInfo='frame '+$msg.renderer+' '+$msg.canvasWidth+'x'+$msg.canvasHeight
                    [IO.File]::WriteAllText((Join-Path $ctl 'webview-renderer.log'),$script:webFrameInfo,(New-Object Text.UTF8Encoding($false)))
                } elseif($msg.type -eq 'jsError'){
                    [IO.File]::AppendAllText((Join-Path $ctl 'webview-errors.log'),([DateTime]::Now.ToString('s')+' '+[string]$msg.message+[Environment]::NewLine))
                } elseif($msg.type -eq 'openUrl' -and $msg.url){
                    Start-Process ([string]$msg.url)
                }
            } catch {}
        })
        $webLog.Source=[Uri]'https://create.local/index.html'
    } catch {
        $script:webRenderer='fallback'
        $script:webReady=$false
        try {
            $webLog.Visible=$false
            $log.Dock='Fill'; $log.Visible=$true
            $form.Controls.Add($log)
            $log.BringToFront()
            [RdcNativeWindow]::ApplyDarkScrollBars($log.Handle)
        } catch {}
        Add-Log ('[WebView2] GPU-лог недоступен, включён WinForms fallback: '+$_.Exception.Message+$nl)
    }
}
function Add-Log([string]$text){
    if([string]::IsNullOrEmpty($text)){return}
    $view=$null
    if(-not $script:smartFollow){try{$view=$log.GetViewPosition()}catch{}}
    $start=$log.TextLength
    $log.AppendText($text)
    Style-LogTail $start
    $log.SelectionStart=$log.TextLength; $log.SelectionLength=0; $log.SelectionColor=$log.ForeColor
    if($script:smartFollow){
        $log.ScrollToCaret()
    } elseif($view) {
        try{$log.SetViewPosition($view.X,$view.Y)}catch{}
    }
    Send-WebLogMessage 'append' $text
}
function Manager {
    try {
        $s=Get-Content (Join-Path $ctl 'state.json') -Raw | ConvertFrom-Json
        $p=Get-Process -Id $s.hostPid -ErrorAction Stop
        if($p.StartTime.ToUniversalTime().Ticks.ToString() -eq $s.hostStarted){return $s}
    } catch {}
    return $null
}
function Start-HiddenControl {
    $control=Join-Path $root 'server-control.ps1'
    $psExe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=$psExe
    $psi.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$control+'" -StartOnly'
    $psi.WorkingDirectory=$root
    $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
    $psi.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
    # Do not redirect stdout/stderr here. server-control starts the long-lived
    # server-manager process, which can inherit redirected pipe handles and keep
    # ReadToEnd() blocked for the entire lifetime of the server.
    $p=New-Object Diagnostics.Process; $p.StartInfo=$psi; [void]$p.Start()
    return @{process=$p}
}
function Run-Control([string]$command){
    if($script:job){return}
    try {
        New-Item -ItemType Directory -Force $ctl | Out-Null
        if($command -eq '__start'){
            Close-Reader
            $script:readerSessionKey=$null; $script:offlineViewShown=$false; $script:sessionEndedShown=$false
            $script:hadActiveSession=$false; $script:smartFollow=$true
            Clear-LogView
            Add-Log ('=== НОВАЯ СЕССИЯ ЗАПУСКАЕТСЯ ==='+$nl+$nl+'> Запуск сервера'+$nl)
            $script:job=Start-HiddenControl
            return
        }
        if($command -match '[\r\n]'){throw 'Команда должна занимать одну строку'}
        if(-not (Manager)){throw 'Сервер остановлен'}
        $request=Join-Path $ctl ([Guid]::NewGuid().ToString('N')+'.request')
        @{command=$command}|ConvertTo-Json|Set-Content ($request+'.tmp') -Encoding UTF8
        Move-Item ($request+'.tmp') $request
        $script:job=@{reply=($request -replace '\.request$','.response');deadline=(Get-Date).AddSeconds(330)}
        Add-Log ($nl+'> '+$command+$nl)
    } catch { Add-Log ('Ошибка: '+$_.Exception.Message+$nl) }
}
$start.Add_Click({Run-Control '__start'})
$stop.Add_Click({Run-Control 'stop'})
$restart.Add_Click({Run-Control 'restart'})
$folder.Add_Click({Start-Process explorer.exe -ArgumentList ('"'+$root+'"')})
$send.Add_Click({
    $c=$commandInput.Text.Trim().TrimStart('/')
    if($c -and -not $script:job){Run-Control $c; $commandInput.Clear()}
})
$commandInput.Add_KeyDown({
    if($_.KeyCode -eq [Windows.Forms.Keys]::Enter){
        $c=$commandInput.Text.Trim().TrimStart('/')
        if($c -and -not $script:job){Run-Control $c; $commandInput.Clear()}
        $_.SuppressKeyPress=$true; $_.Handled=$true
    }
})
$menuColors=New-Object RdcMenuColorTable
$menuRenderer=New-Object Windows.Forms.ToolStripProfessionalRenderer -ArgumentList $menuColors
$helpMenu=New-Object Windows.Forms.ContextMenuStrip
$helpMenu.BackColor=[Drawing.Color]::FromArgb(38,41,46); $helpMenu.ForeColor=[Drawing.Color]::Gainsboro; $helpMenu.Renderer=$menuRenderer
$aboutItem=New-Object Windows.Forms.ToolStripMenuItem; $aboutItem.Text='Справка / О программе'
$openLogItem=New-Object Windows.Forms.ToolStripMenuItem; $openLogItem.Text='Открыть текущий журнал'
$openLogsFolderItem=New-Object Windows.Forms.ToolStripMenuItem; $openLogsFolderItem.Text='Папка журналов'
[void]$helpMenu.Items.Add($aboutItem); [void]$helpMenu.Items.Add($openLogItem); [void]$helpMenu.Items.Add($openLogsFolderItem)
$helpButton.Add_Click({$helpMenu.Show($helpButton,(New-Object Drawing.Point(10,$helpButton.Height)))})
$aboutItem.Add_Click({
    $text='Copperline Deck | Minecraft Server'+$nl+$nl+
      'Графическая оболочка для управления локальным Fabric Minecraft-сервером.'+$nl+$nl+
      '«Запустить» — запускает сервер. «Остановить» — сохраняет мир и корректно завершает Java.'+$nl+
      '«Перезапустить» — выполняет штатный stop и новый запуск. «Папка сервера» — открывает каталог сервера.'+$nl+$nl+
      'В окне показывается только текущая серверная сессия. История хранится в папке logs.'+$nl+
      'Закрытие этого окна не останавливает Minecraft-сервер.'
    [Windows.Forms.MessageBox]::Show($text,'Copperline Deck — справка',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Information)|Out-Null
})
$openLogItem.Add_Click({
    try {
        if(-not (Test-Path $logPath)){throw 'Журнал ещё не создан.'}
        $notepad=Join-Path $env:SystemRoot 'System32\notepad.exe'
        Start-Process -FilePath $notepad -ArgumentList ('"'+$logPath+'"')
    } catch {
        [Windows.Forms.MessageBox]::Show(('Не удалось открыть журнал.'+$nl+$nl+$_.Exception.Message),'Copperline Deck — журнал',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error)|Out-Null
    }
})
$openLogsFolderItem.Add_Click({
    try { Start-Process explorer.exe -ArgumentList ('"'+(Join-Path $root 'logs')+'"') } catch {}
})
function Close-Reader {
    if($script:reader){
        try{$script:reader.Dispose()}catch{}
        $script:reader=$null
    }
}
function Open-Reader([int64]$startOffset,[bool]$skipPartialLine){
    if($script:reader -or -not (Test-Path $logPath)){return}
    try {
        $stream=New-Object IO.FileStream($logPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        $actual=[int64][Math]::Max(0,[Math]::Min($startOffset,$stream.Length))
        [void]$stream.Seek($actual,[IO.SeekOrigin]::Begin)
        $script:reader=New-Object IO.StreamReader($stream,[Text.Encoding]::UTF8,$true,4096)
        if($skipPartialLine -and $actual -gt 0){[void]$script:reader.ReadLine()}
    } catch {
        try{$stream.Dispose()}catch{}
        $script:reader=$null
    }
}
$logReadChunkChars=24576
function Move-ReaderToRecentTailIfBehind {
    if(-not $script:reader){return}
    try {
        $stream=$script:reader.BaseStream
        $remaining=[int64]($stream.Length-$stream.Position)
        if($remaining -le $logCatchupThresholdBytes){return}
        $target=[int64][Math]::Max(0,$stream.Length-$logCatchupTailBytes)
        $script:reader.DiscardBufferedData()
        [void]$stream.Seek($target,[IO.SeekOrigin]::Begin)
        if($target -gt 0){[void]$script:reader.ReadLine()}
        $skippedKB=[Math]::Max(1,[Math]::Round(($remaining-$logCatchupTailBytes)/1KB))
        Add-Log ($nl+'['+(Get-Date -Format 'HH:mm:ss')+'] Live-вывод отстал. Пропущено около '+$skippedKB+' КБ старых строк текущей сессии; показан свежий хвост.'+$nl)
    } catch {}
}
function Drain-ReaderTail {
    if(-not $script:reader){return}
    for($i=0;$i -lt 8;$i++){
        $chunk=[RdcLogBox]::ReadChunk($script:reader,$logReadChunkChars)
        if(-not $chunk){break}
        Add-Log $chunk
    }
}
function Get-SessionKey([object]$s){
    if(-not $s){return $null}
    if($s.PSObject.Properties['sessionStartedUtc'] -and -not [string]::IsNullOrWhiteSpace([string]$s.sessionStartedUtc)){
        return [string]$s.sessionStartedUtc
    }
    $offset=if($s.PSObject.Properties['logStartOffset']){[string]$s.logStartOffset}else{'legacy'}
    return ([string]$s.hostStarted+':'+$offset)
}
function Show-OfflineLogView {
    Close-Reader
    $script:readerSessionKey=$null
    if($script:offlineViewShown){return}
    $script:smartFollow=$true
    Clear-LogView
    Add-Log ('=== СЕРВЕР ОСТАНОВЛЕН ==='+$nl+$nl+
        'Нажмите «Запустить», чтобы начать новую сессию.'+$nl+
        'Старые серверные логи здесь не подгружаются; история доступна через «? → Папка журналов».'+$nl)
    $script:offlineViewShown=$true
}
function Read-LiveLog([object]$s,[bool]$busy){
    if(-not $s){
        if($script:hadActiveSession){
            if($script:reader){Drain-ReaderTail;Close-Reader}
            if(-not $script:sessionEndedShown){
                Add-Log ($nl+'=== СЕССИЯ ЗАВЕРШЕНА ==='+$nl)
                $script:sessionEndedShown=$true
            }
        } elseif(-not $busy) {
            Show-OfflineLogView
        }
        return
    }

    $script:hadActiveSession=$true
    $script:offlineViewShown=$false
    $script:sessionEndedShown=$false
    $key=Get-SessionKey $s
    if($script:readerSessionKey -ne $key){
        Close-Reader
        $script:readerSessionKey=$key
        $script:smartFollow=$true
        Clear-LogView

        $when=''
        if($s.PSObject.Properties['sessionStartedUtc'] -and -not [string]::IsNullOrWhiteSpace([string]$s.sessionStartedUtc)){
            try{$when=([DateTime]::Parse([string]$s.sessionStartedUtc)).ToLocalTime().ToString('dd.MM.yyyy HH:mm:ss')}catch{}
        }
        $banner=if($when){'=== ТЕКУЩАЯ СЕССИЯ • '+$when+' ==='}else{'=== ТЕКУЩАЯ СЕССИЯ ==='}
        Add-Log ($banner+$nl+$nl)

        $fallback=$true
        $offset=[int64]0
        if($s.PSObject.Properties['logStartOffset']){
            try{$offset=[int64]$s.logStartOffset;$fallback=$false}catch{}
        }
        if($fallback -and (Test-Path $logPath)){
            $len=[int64](Get-Item -LiteralPath $logPath).Length
            $offset=[Math]::Max(0,$len-$logCatchupTailBytes)
        }
        Open-Reader $offset $fallback
    }

    if($script:reader){
        Move-ReaderToRecentTailIfBehind
        $chunk=[RdcLogBox]::ReadChunk($script:reader,$logReadChunkChars)
        if($chunk){Add-Log $chunk}
    }
}
function Update-Service([object]$s,[bool]$busy){
    $running=$s -and $s.status -eq 'running'
    $start.Enabled=(-not $s -and -not $busy)
    $stop.Enabled=($running -and -not $busy); $restart.Enabled=$stop.Enabled; $send.Enabled=$stop.Enabled
    $pidLabel.Text='Java PID: —'; $ramLabel.Text='Память: —'; $uptimeLabel.Text='Время работы: —'
    if($s -and $s.javaPid){
        try {
            $j=Get-Process -Id $s.javaPid -ErrorAction Stop
            $pidLabel.Text='Java PID: '+$j.Id
            $ramLabel.Text=('Память: {0:F2} ГБ' -f ($j.WorkingSet64/1GB))
            $elapsed=(Get-Date)-$j.StartTime
            $uptimeLabel.Text=('Время работы: {0:00}:{1:00}:{2:00}' -f [int]$elapsed.TotalHours,$elapsed.Minutes,$elapsed.Seconds)
        } catch {}
    }
    if(-not $s){
        if($busy){Set-State 'Запускается' 'Minecraft-сервер запускается…' $accentOrange}
        else{Set-State 'Остановлен' 'Minecraft-сервер сейчас не запущен.' ([Drawing.Color]::FromArgb(128,132,138))}
        return
    }
    $raw=[string]$s.status
    if($raw -eq 'running'){
        $msg='Minecraft-сервер запущен и готов принимать игроков.'
        if($busy){$msg+=' Выполняется команда…'}
        Set-State 'Работает' $msg ([Drawing.Color]::FromArgb(76,190,112))
    } elseif($raw -eq 'starting'){
        Set-State 'Запускается' 'Minecraft-сервер запускается…' $accentOrange
    } elseif($raw -eq 'stopping'){
        Set-State 'Останавливается' 'Сохраняет мир и корректно завершает Java…' $accentOrange
    } elseif($raw -like 'error:*'){
        Set-State 'Ошибка' ($raw.Substring(6).Trim()) ([Drawing.Color]::FromArgb(214,86,86))
    } else {
        Set-State 'Остановлен' 'Minecraft-сервер остановлен.' ([Drawing.Color]::FromArgb(128,132,138))
    }
}
function Refresh-Window {
    Apply-SystemFrameTheme
    $s=Manager
    Read-LiveLog $s ($null -ne $script:job)
    if($script:job){
        if($script:job.reply){
            if(Test-Path $script:job.reply){
                $r=Get-Content $script:job.reply -Raw|ConvertFrom-Json
                Add-Log ($r.message+$nl); Remove-Item $script:job.reply; $script:job=$null
            } elseif((Get-Date)-gt $script:job.deadline){
                Add-Log ('Тайм-аут команды. Проверьте журнал.'+$nl); $script:job=$null
            }
        } elseif($script:job.process.HasExited){
            $exitCode=$script:job.process.ExitCode
            if($exitCode -ne 0){
                Add-Log ('Не удалось запустить сервер (код '+$exitCode+'). Проверьте .control\manager-errors.log и основной журнал.'+$nl)
            }
            $script:job.process.Dispose(); $script:job=$null
        }
    }
    $s=Manager
    Update-Service $s ($null -ne $script:job)
}
$timer=New-Object Windows.Forms.Timer
$timer.Interval=650
$timer.Add_Tick({
    if($activateEvent -and $activateEvent.WaitOne(0)){
        if($form.WindowState -eq 'Minimized'){$form.WindowState='Normal'}
        $form.Show(); [void]$form.Activate()
    }
    Refresh-Window
})
$visibilityTimer=New-Object Windows.Forms.Timer
$visibilityTimer.Interval=1000
$visibilityTimer.Add_Tick({Update-FxVisibility $false})
$form.Add_Resize({Update-FxVisibility $true})
$form.Add_VisibleChanged({Update-FxVisibility $true})
$form.Add_Activated({Update-FxVisibility $true})
$form.Add_Shown({
    Apply-SystemFrameTheme
    Initialize-WebLog
})
$form.Add_FormClosed({
    $timer.Stop()
    $visibilityTimer.Stop()
    if($script:reader){$script:reader.Dispose()}
})
Refresh-Window
if($SelfTest){
    if($log.GetType().Name -ne 'RdcLogBox'){throw 'Custom log control missing'}
    if($log.ScrollBars -ne [Windows.Forms.RichTextBoxScrollBars]::Both){throw 'Native server scrollbars changed'}
    if([Math]::Abs($log.ZoomFactor-1.0)-gt 0.001){throw 'Log zoom must be 100 percent'}
    if($form.Width -gt $startupWorkArea.Width -or $form.Height -gt $startupWorkArea.Height){throw 'Initial window exceeds working area'}
    if(-not $log.WordWrap){throw 'Log word wrap must be enabled'}
    if($webLog.GetType().Name -ne 'WebView2'){throw 'WebView2 log control missing'}
    if(-not (Test-Path (Join-Path $webView2Root 'Microsoft.Web.WebView2.Core.dll')) -or -not (Test-Path (Join-Path $webUiRoot 'pixi.min.js')) -or -not (Test-Path (Join-Path $webUiRoot 'index.html')) -or -not (Test-Path (Join-Path $webUiRoot 'app.js'))){throw 'WebView2/Pixi assets missing'}
    if($start.Glyph -ne 'play' -or $stop.Glyph -ne 'stop' -or $restart.Glyph -ne 'restart' -or $folder.Glyph -ne 'folder' -or $send.Glyph -ne 'send'){throw 'Action glyphs missing'}
    $legacyFollow=('$fol'+'low')
    if(Select-String -LiteralPath $PSCommandPath -SimpleMatch $legacyFollow -Quiet){throw 'Legacy auto-scroll checkbox reference remains'}

    $manager=Manager
    if($manager){
        Run-Control 'list'
        $limit=(Get-Date).AddSeconds(15)
        while($script:job -and (Get-Date)-lt $limit){Start-Sleep -Milliseconds 250;Refresh-Window}
        if($script:job){throw 'Command test timed out'}
        $logDeadline=(Get-Date).AddSeconds(5)
        while($log.Text -notmatch 'players online' -and (Get-Date)-lt $logDeadline){
            Read-LiveLog (Manager) $false
            Start-Sleep -Milliseconds 80
        }
        if($log.Text -notmatch 'players online'){throw 'Minecraft reply missing'}
    } else {
        if($log.Text -notmatch 'СЕРВЕР ОСТАНОВЛЕН'){throw 'Offline session placeholder missing'}
        if($log.Text -match 'Server thread/INFO'){throw 'Old server history leaked into offline view'}
    }

    Close-Reader
    $originalLogPath=$logPath
    $tempSessionLog=Join-Path $env:TEMP ('create-session-selftest-'+[Guid]::NewGuid().ToString('N')+'.log')
    try {
        $oldPart='OLD_SESSION_LINE'+$nl
        $newPart='NEW_SESSION_LINE'+$nl
        [IO.File]::WriteAllText($tempSessionLog,($oldPart+$newPart),(New-Object Text.UTF8Encoding($false)))
        $logPath=$tempSessionLog
        $offset=[Text.Encoding]::UTF8.GetByteCount($oldPart)
        $script:readerSessionKey=$null
        $script:hadActiveSession=$false
        $script:offlineViewShown=$false
        $fake=[pscustomobject]@{hostStarted='selftest';status='running';javaPid=0;logStartOffset=$offset;sessionStartedUtc='2026-10-04T00:00:00.0000000Z'}
        Read-LiveLog $fake $false
        if($log.Text -match 'OLD_SESSION_LINE' -or $log.Text -notmatch 'NEW_SESSION_LINE'){throw 'Session log boundary failed'}

        Add-Log ($nl+'[00:00:00] [Server thread/WARN]: WARN_TEST'+$nl+
            '[00:00:00] [Server thread/ERROR]: ERROR_TEST'+$nl+
            '[00:00:00] [Server thread/INFO]: Done (1.000s)! For help, type "help" READY_TEST'+$nl+
            '> list COMMAND_TEST'+$nl)
        foreach($probe in @(
            @('WARN_TEST',$logWarn,'WARN color failed'),
            @('ERROR_TEST',$logError,'ERROR color failed'),
            @('READY_TEST',$logReady,'Ready color failed'),
            @('COMMAND_TEST',$logCommand,'Command color failed')
        )){
            $pos=$log.Text.IndexOf([string]$probe[0],[StringComparison]::Ordinal)
            if($pos -lt 0){throw ([string]$probe[2]+' (missing)')}
            $log.Select($pos,1)
            if($log.SelectionColor.ToArgb() -ne ([Drawing.Color]$probe[1]).ToArgb()){throw [string]$probe[2]}
        }
    } finally {
        Close-Reader
        $logPath=$originalLogPath
        Remove-Item -LiteralPath $tempSessionLog -Force -ErrorAction SilentlyContinue
    }
    $log.Select($log.TextLength,0)
    if($log.SelectionLength -ne 0){throw 'Unexpected visible selection'}
    $mode=if($manager){'online'}else{'offline'}
    Write-Output ('GUI TEST PASSED ('+$mode+'); sessionBoundary=ok; semanticColors=ok; glyphs=ok; webview=staged; title='+$title.Text)
    $form.Dispose(); exit 0
}
$timer.Start()
$visibilityTimer.Start()
try{[Windows.Forms.Application]::Run($form)}
finally{
    if($windowMutex){$windowMutex.ReleaseMutex();$windowMutex.Dispose()}
    if($activateEvent){$activateEvent.Dispose()}
}
