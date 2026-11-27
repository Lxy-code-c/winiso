<# ============================================================================
  winiso / gui / WinIsoGui.ps1  ——  图形界面（WPF，纯 PowerShell，无 Python）
  由 WinIsoGui.cmd 或 winiso.exe 启动（必须是 STA 线程）
============================================================================ #>

$ErrorActionPreference = 'Stop'
$script:Root = Split-Path -Parent $PSScriptRoot

. (Join-Path $script:Root 'lib\common.ps1')
. (Join-Path $script:Root 'lib\uup.ps1')
. (Join-Path $script:Root 'lib\converter.ps1')
. (Join-Path $script:Root 'lib\slim.ps1')

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# PD VM / no GPU: WPF hardware acceleration renders a blank window, force software rendering
[System.Windows.Media.RenderOptions]::ProcessRenderMode = [System.Windows.Interop.RenderMode]::SoftwareOnly
Add-Type -AssemblyName System.Windows.Forms

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="winiso  —  Windows ISO Builder"
        Height="840" Width="1080" MinHeight="700" MinWidth="960"
        WindowStartupLocation="CenterScreen"
        Background="#0E1015"
        FontFamily="Microsoft YaHei UI"
        Foreground="#E6EAF2">
  <Window.Resources>
    <SolidColorBrush x:Key="CardBg" Color="#171A22"/>
    <SolidColorBrush x:Key="CardBorder" Color="#272C38"/>
    <SolidColorBrush x:Key="Accent" Color="#5B8DEF"/>
    <SolidColorBrush x:Key="Muted" Color="#8B93A7"/>

    <Style x:Key="Card" TargetType="Border">
      <Setter Property="Background" Value="{StaticResource CardBg}"/>
      <Setter Property="BorderBrush" Value="{StaticResource CardBorder}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="12"/>
      <Setter Property="Padding" Value="18,12,18,12"/>
      <Setter Property="Margin" Value="0,0,0,10"/>
    </Style>

    <Style x:Key="CardTitle" TargetType="TextBlock">
      <Setter Property="Foreground" Value="{StaticResource Accent}"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Margin" Value="0,0,0,10"/>
    </Style>

    <Style TargetType="ComboBoxItem">
      <Setter Property="Foreground" Value="#E6EAF2"/>
      <Setter Property="Padding" Value="10,7,10,7"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBoxItem">
            <Border x:Name="bd" Background="Transparent" Padding="{TemplateBinding Padding}" CornerRadius="6">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#243040"/>
              </Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#2C3D5C"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="ComboBox">
      <Setter Property="Height" Value="34"/>
      <Setter Property="Background" Value="#11141B"/>
      <Setter Property="Foreground" Value="#E6EAF2"/>
      <Setter Property="BorderBrush" Value="#2E3542"/>
      <Setter Property="Padding" Value="8,0,8,0"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBox">
            <Grid>
              <ToggleButton x:Name="Toggle" ClickMode="Press" Focusable="False"
                            IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">
                <ToggleButton.Template>
                  <ControlTemplate TargetType="ToggleButton">
                    <Border CornerRadius="8" Background="#11141B" BorderBrush="#2E3542" BorderThickness="1">
                      <Grid>
                        <Grid.ColumnDefinitions>
                          <ColumnDefinition Width="*"/>
                          <ColumnDefinition Width="26"/>
                        </Grid.ColumnDefinitions>
                        <ContentPresenter Grid.Column="0" Margin="10,0,0,0" VerticalAlignment="Center"
                                          Content="{Binding SelectionBoxItem, RelativeSource={RelativeSource AncestorType=ComboBox}}"
                                          ContentTemplate="{Binding SelectionBoxItemTemplate, RelativeSource={RelativeSource AncestorType=ComboBox}}"/>
                        <Path Grid.Column="1" Data="M0,0 L8,0 L4,5 Z" Fill="#8B93A7"
                              HorizontalAlignment="Center" VerticalAlignment="Center"/>
                      </Grid>
                    </Border>
                  </ControlTemplate>
                </ToggleButton.Template>
              </ToggleButton>
              <Popup x:Name="PART_Popup" IsOpen="{TemplateBinding IsDropDownOpen}"
                     AllowsTransparency="True" Placement="Bottom" Focusable="False" PopupAnimation="Slide">
                <Border Background="#171A22" BorderBrush="#2E3542" BorderThickness="1" CornerRadius="8"
                        MinWidth="{TemplateBinding ActualWidth}"
                        MaxHeight="320" Margin="0,4,0,0">
                  <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <ItemsPresenter/>
                  </ScrollViewer>
                </Border>
              </Popup>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="#D7DCE6"/>
      <Setter Property="Margin" Value="0,5,18,5"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
    </Style>

    <Style TargetType="RadioButton">
      <Setter Property="Foreground" Value="#D7DCE6"/>
      <Setter Property="Margin" Value="0,4,18,4"/>
    </Style>

    <Style x:Key="Ghost" TargetType="Button">
      <Setter Property="Background" Value="#232937"/>
      <Setter Property="Foreground" Value="#E6EAF2"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="14,6"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Primary" TargetType="Button">
      <Setter Property="Background" Value="{StaticResource Accent}"/>
      <Setter Property="Foreground" Value="#0B1220"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="22,9"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="9" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#7BA4F5"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="bd" Property="Background" Value="#39404F"/>
                <Setter Property="Foreground" Value="#8B93A7"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="StepDot" TargetType="TextBlock">
      <Setter Property="Foreground" Value="#6D7688"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Margin" Value="0,0,0,22"/>
    </Style>
  </Window.Resources>

  <Grid Margin="0">
    <Grid.RowDefinitions>
      <RowDefinition Height="86"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="82"/>
    </Grid.RowDefinitions>

    <!-- 顶栏 -->
    <Border Grid.Row="0" Background="#141821" BorderBrush="#20242E" BorderThickness="0,0,0,1">
      <Grid Margin="26,0,26,0">
        <StackPanel VerticalAlignment="Center">
          <TextBlock Text="winiso" FontSize="26" FontWeight="Bold" Foreground="#FFFFFF"/>
          <TextBlock Text="UUP 官方源 · 任意版本 / 任意架构 · 精简 + 广告拦截 + macOS 风格" FontSize="12" Foreground="#8B93A7" Margin="0,4,0,0"/>
        </StackPanel>
        <StackPanel HorizontalAlignment="Right" VerticalAlignment="Center" Orientation="Horizontal">
          <TextBlock x:Name="TxtAdmin" Text="正在检测权限..." FontSize="12" Foreground="#8B93A7"/>
        </StackPanel>
      </Grid>
    </Border>

    <!-- 主体 -->
    <Grid Grid.Row="1" Margin="26,20,26,0">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="210"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <!-- 左侧步骤 -->
      <StackPanel Grid.Column="0" Margin="0,4,20,0">
        <TextBlock Text="流 程" FontSize="11" Foreground="#5F6779" Margin="0,0,0,14"/>
        <TextBlock x:Name="Step1" Text="①  指定版本" Style="{StaticResource StepDot}" Foreground="#5B8DEF" FontWeight="SemiBold"/>
        <TextBlock x:Name="Step2" Text="②  选择操作与美化" Style="{StaticResource StepDot}"/>
        <TextBlock x:Name="Step3" Text="③  开始生成" Style="{StaticResource StepDot}"/>
        <Border Height="1" Background="#232833" Margin="0,6,0,16"/>
        <TextBlock Text="提示" FontSize="11" Foreground="#5F6779" Margin="0,0,0,8"/>
        <TextBlock TextWrapping="Wrap" FontSize="11.5" Foreground="#77808F" LineHeight="18"
                   Text="· 下载约 7-8 GB，全程约 60-120 分钟&#10;· 工作目录建议放 E 盘，需要 30 GB 以上&#10;· 中途关窗会中断，重跑会接着下（已下好的不再重下）"/>
      </StackPanel>

      <!-- 右侧内容 -->
      <ScrollViewer Grid.Column="1" VerticalScrollBarVisibility="Auto" Padding="0,0,8,0">
        <StackPanel>

          <!-- 版本 -->
          <Border Style="{StaticResource Card}">
            <StackPanel>
              <TextBlock Text="① 指定版本" Style="{StaticResource CardTitle}"/>
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="1.1*"/>
                  <ColumnDefinition Width="0.9*"/>
                  <ColumnDefinition Width="2.2*"/>
                  <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="34"/>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="34"/>
                </Grid.RowDefinitions>

                <TextBlock Grid.Row="0" Grid.Column="0" Text="系统家族" FontSize="11" Foreground="#8B93A7" Margin="0,0,0,5"/>
                <ComboBox x:Name="CmbFamily" Grid.Row="1" Grid.Column="0" Margin="0,0,10,12"/>

                <TextBlock Grid.Row="0" Grid.Column="1" Text="架构" FontSize="11" Foreground="#8B93A7" Margin="0,0,0,5"/>
                <ComboBox x:Name="CmbArch" Grid.Row="1" Grid.Column="1" Margin="0,0,10,12"/>

                <TextBlock Grid.Row="0" Grid.Column="2" Text="构建（正式版，最新在上）" FontSize="11" Foreground="#8B93A7" Margin="0,0,0,5"/>
                <ComboBox x:Name="CmbBuild" Grid.Row="1" Grid.Column="2" Margin="0,0,10,12"/>

                <Button x:Name="BtnLoad" Grid.Row="1" Grid.Column="3" Content="加载构建" Style="{StaticResource Ghost}" Margin="0,0,0,12"/>

                <TextBlock Grid.Row="2" Grid.Column="0" Text="语言" FontSize="11" Foreground="#8B93A7" Margin="0,0,0,5"/>
                <ComboBox x:Name="CmbLang" Grid.Row="3" Grid.Column="0" Margin="0,0,10,0"/>

                <TextBlock Grid.Row="2" Grid.Column="1" Text="版本种类" FontSize="11" Foreground="#8B93A7" Margin="0,0,0,5"/>
                <ComboBox x:Name="CmbEdition" Grid.Row="3" Grid.Column="1" Grid.ColumnSpan="2" Margin="0,0,10,0"/>
              </Grid>
            </StackPanel>
          </Border>

          <!-- 操作 -->
          <Border Style="{StaticResource Card}">
            <StackPanel>
              <TextBlock Text="② 选择操作" Style="{StaticResource CardTitle}"/>
              <WrapPanel x:Name="OpsPanel" Orientation="Horizontal"/>
              <TextBlock Text="注：勾选「macOS 风格」后，下面会展开美化细节。" FontSize="11" Foreground="#77808F" Margin="0,8,0,0"/>
            </StackPanel>
          </Border>

          <!-- 美化细节 -->
          <Border x:Name="BeautyCard" Style="{StaticResource Card}" Visibility="Collapsed">
            <StackPanel>
              <TextBlock Text="  美化细节（可单独开关）" Style="{StaticResource CardTitle}"/>
              <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                <TextBlock Text="主题：" FontSize="12" Foreground="#8B93A7" VerticalAlignment="Center"/>
                <RadioButton x:Name="RbDark" Content="深色（推荐）" GroupName="theme" IsChecked="True"/>
                <RadioButton x:Name="RbLight" Content="浅色" GroupName="theme"/>
              </StackPanel>
              <WrapPanel x:Name="BeautyPanel" Orientation="Horizontal"/>
            </StackPanel>
          </Border>

          <!-- 路径 -->
          <Border Style="{StaticResource Card}">
            <StackPanel>
              <TextBlock Text="③ 输出位置" Style="{StaticResource CardTitle}"/>
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="Auto"/>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="34"/>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="34"/>
                </Grid.RowDefinitions>

                <TextBlock Grid.Row="0" Grid.Column="0" Grid.ColumnSpan="3" Text="工作目录（下载与转换，需要 30 GB）" FontSize="11" Foreground="#8B93A7" Margin="0,0,0,5"/>
                <TextBox x:Name="TxtWork" Grid.Row="1" Grid.Column="0" Grid.ColumnSpan="2" Height="34" VerticalContentAlignment="Center"
                         Background="#11141B" Foreground="#E6EAF2" BorderBrush="#2E3542" Padding="8,0"/>
                <Button x:Name="BtnWork" Grid.Row="1" Grid.Column="2" Content="浏览" Style="{StaticResource Ghost}" Margin="10,0,0,12"/>

                <TextBlock Grid.Row="2" Grid.Column="0" Grid.ColumnSpan="3" Text="ISO 输出目录（与原版分开放）" FontSize="11" Foreground="#8B93A7" Margin="0,0,0,5"/>
                <TextBox x:Name="TxtOut" Grid.Row="3" Grid.Column="0" Grid.ColumnSpan="2" Height="34" VerticalContentAlignment="Center"
                         Background="#11141B" Foreground="#E6EAF2" BorderBrush="#2E3542" Padding="8,0"/>
                <Button x:Name="BtnOut" Grid.Row="3" Grid.Column="2" Content="浏览" Style="{StaticResource Ghost}" Margin="10,0,0,0"/>
              </Grid>
            </StackPanel>
          </Border>

          <!-- 日志 -->
          <Border Style="{StaticResource Card}">
            <StackPanel>
              <TextBlock Text="进度日志" Style="{StaticResource CardTitle}"/>
              <TextBox x:Name="LogBox" Height="150" IsReadOnly="True" AcceptsReturn="True"
                       VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
                       Background="#0B0D12" Foreground="#AEB7C6" BorderBrush="#232833"
                       FontFamily="Consolas" FontSize="12" Padding="10" TextWrapping="NoWrap"
                       Text="等待开始。选择版本与操作后点右下角「开始生成」。"/>
            </StackPanel>
          </Border>

        </StackPanel>
      </ScrollViewer>
    </Grid>

    <!-- 底栏 -->
    <Border Grid.Row="2" Background="#141821" BorderBrush="#20242E" BorderThickness="0,1,0,0">
      <Grid Margin="26,0,26,0">
        <StackPanel VerticalAlignment="Center">
          <TextBlock x:Name="TxtStatus" Text="就绪" FontSize="13" Foreground="#E6EAF2"/>
          <TextBlock x:Name="TxtSub" Text="未开始" FontSize="11" Foreground="#77808F" Margin="0,3,0,0"/>
        </StackPanel>
        <StackPanel HorizontalAlignment="Right" VerticalAlignment="Center" Orientation="Horizontal">
          <Button x:Name="BtnDiag" Content="诊断下载" Style="{StaticResource Ghost}" Margin="0,0,12,0"/>
          <Button x:Name="BtnOpen" Content="打开输出目录" Style="{StaticResource Ghost}" Margin="0,0,12,0" IsEnabled="False"/>
          <Button x:Name="BtnStart" Content="开始生成" Style="{StaticResource Primary}"/>
        </StackPanel>
      </Grid>
    </Border>
  </Grid>
</Window>
'@

$script:win = [Windows.Markup.XamlReader]::Parse($xaml)

function Get-Element([string]$Name) { return $script:win.FindName($Name) }

$script:CmbFamily  = Get-Element 'CmbFamily'
$script:CmbArch    = Get-Element 'CmbArch'
$script:CmbBuild   = Get-Element 'CmbBuild'
$script:CmbLang    = Get-Element 'CmbLang'
$script:CmbEdition = Get-Element 'CmbEdition'
$script:BtnLoad    = Get-Element 'BtnLoad'
$script:OpsPanel   = Get-Element 'OpsPanel'
$script:BeautyPanel= Get-Element 'BeautyPanel'
$script:BeautyCard = Get-Element 'BeautyCard'
$script:RbDark     = Get-Element 'RbDark'
$script:RbLight    = Get-Element 'RbLight'
$script:TxtWork    = Get-Element 'TxtWork'
$script:TxtOut     = Get-Element 'TxtOut'
$script:BtnWork    = Get-Element 'BtnWork'
$script:BtnOut     = Get-Element 'BtnOut'
$script:LogBox     = Get-Element 'LogBox'
$script:BtnStart   = Get-Element 'BtnStart'
$script:BtnDiag    = Get-Element 'BtnDiag'
$script:BtnOpen    = Get-Element 'BtnOpen'
$script:TxtStatus  = Get-Element 'TxtStatus'
$script:TxtSub     = Get-Element 'TxtSub'
$script:TxtAdmin   = Get-Element 'TxtAdmin'
$script:Step1      = Get-Element 'Step1'
$script:Step2      = Get-Element 'Step2'
$script:Step3      = Get-Element 'Step3'

# ---------------------------------------------------------------- 数据
$script:OpsItems = @(
    @{ V='slim';      L='精简组件';        H='删 Copilot / Bing / Xbox 等预置应用与冗余包'; On=$true },
    @{ V='adblock';   L='广告与追踪拦截';  H='写 hosts，装机即全局屏蔽广告与遥测域名';     On=$true },
    @{ V='mac';       L='macOS 风格';      H='居中任务栏 / 深色 / 透明 / 自绘壁纸';         On=$true },
    @{ V='unattend';  L='无人值守安装';    H='跳过 TPM / 安全启动检测与联网 OOBE';          On=$true },
    @{ V='nowinre';   L='移除 WinRE';      H='省约 500 MB，失去恢复环境';                   On=$false },
    @{ V='noedge';    L='移除 Edge';       H='激进，可能影响部分组件';                      On=$false },
    @{ V='netfx3';    L='集成 .NET 3.5';   H='部分老软件需要';                              On=$false },
    @{ V='resetbase'; L='ResetBase 清理';  H='显著缩小体积，之后无法卸载更新';              On=$false },
    @{ V='skipapps';  L='跳过商店应用';    H='更快，商店应用不被预置';                      On=$true }
)

$script:BeautyItems = @(
    @{ V='SmallIcons'; L='任务栏小图标';   On=$true  },
    @{ V='Seconds';    L='时钟显示秒';     On=$true  },
    @{ V='Explorer';   L='资源管理器整理'; On=$true  },
    @{ V='Wallpaper';  L='自绘渐变壁纸';   On=$true  },
    @{ V='Spotlight';  L='Spotlight 搜索'; On=$true  },
    @{ V='Dock';       L='程序坞 Dock';    On=$false }
)

$script:OpsChecks = @{}
$script:BeautyChecks = @{}

foreach ($item in $script:OpsItems) {
    $cb = New-Object System.Windows.Controls.CheckBox
    $cb.Content = $item.L
    $cb.IsChecked = [bool]$item.On
    $cb.ToolTip = $item.H
    $cb.Tag = $item.V
    $cb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#D7DCE6')
    $cb.Margin = [System.Windows.Thickness]::new(0, 4, 22, 4)
    if ($item.V -eq 'mac') {
        $cb.Add_Checked({ param($s, $e) $script:BeautyCard.Visibility = 'Visible' })
        $cb.Add_Unchecked({ param($s, $e) $script:BeautyCard.Visibility = 'Collapsed' })
    }
    [void]$script:OpsPanel.Children.Add($cb)
    $script:OpsChecks[$item.V] = $cb
    if ($item.V -eq 'mac' -and $cb.IsChecked) { $script:BeautyCard.Visibility = 'Visible' }
}

foreach ($item in $script:BeautyItems) {
    $cb = New-Object System.Windows.Controls.CheckBox
    $cb.Content = $item.L
    $cb.IsChecked = [bool]$item.On
    $cb.Tag = $item.V
    $cb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#D7DCE6')
    $cb.Margin = [System.Windows.Thickness]::new(0, 4, 22, 4)
    [void]$script:BeautyPanel.Children.Add($cb)
    $script:BeautyChecks[$item.V] = $cb
}

# 家族 / 架构
foreach ($f in @(
    @{ Label='Windows 11'; Value='win11' },
    @{ Label='Windows 10'; Value='win10' },
    @{ Label='Windows Server'; Value='server' }
)) {
    [void]$script:CmbFamily.Items.Add((New-Object System.Windows.Controls.ComboBoxItem -Property @{ Content = $f.Label; Tag = $f.Value }))
}
$script:CmbFamily.SelectedIndex = 0
foreach ($a in @(@{ Label='x64 (amd64)'; Value='amd64' }, @{ Label='ARM64'; Value='arm64' })) {
    [void]$script:CmbArch.Items.Add((New-Object System.Windows.Controls.ComboBoxItem -Property @{ Content = $a.Label; Tag = $a.Value }))
}
$script:CmbArch.SelectedIndex = 0

# 默认目录：优先 E 盘（约定别放 C 盘）-> D 盘 -> 用户目录
$freeE = Get-FreeSpaceGB 'E:\'
if ($freeE -gt 0) {
    $script:TxtWork.Text = 'E:\ISO\work'
    $script:TxtOut.Text  = 'E:\ISO\out'
} else {
    $freeD = Get-FreeSpaceGB 'D:\'
    if ($freeD -gt 0) {
        $script:TxtWork.Text = 'D:\ISO\work'
        $script:TxtOut.Text  = 'D:\ISO\out'
    } else {
        $script:TxtWork.Text = (Join-Path $env:USERPROFILE 'winiso\work')
        $script:TxtOut.Text  = (Join-Path $env:USERPROFILE 'winiso\out')
    }
}

if (Test-Admin) {
    $script:TxtAdmin.Text = '管理员权限：已获取'
    $script:TxtAdmin.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#5DD39E')
} else {
    $script:TxtAdmin.Text = '将以管理员身份重新启动生成任务'
    $script:TxtAdmin.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#F2C14E')
}

# ---------------------------------------------------------------- 工具
function Set-Status([string]$Main, [string]$Sub = '') {
    $script:TxtStatus.Text = $Main
    if ($Sub) { $script:TxtSub.Text = $Sub }
}

function Set-Step([int]$Index) {
    $on  = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#5B8DEF')
    $off = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#6D7688')
    $script:Step1.Foreground = $(if ($Index -ge 1) { $on } else { $off })
    $script:Step2.Foreground = $(if ($Index -ge 2) { $on } else { $off })
    $script:Step3.Foreground = $(if ($Index -ge 3) { $on } else { $off })
}

function Get-SelectedTag($Combo) {
    if ($null -eq $Combo.SelectedItem) { return $null }
    return $Combo.SelectedItem.Tag
}

$script:LogFile = $null
$script:ElevatedProc = $null
$script:TailTimer = $null
$script:ResultIso = $null
$script:ReadOffset = 0

function Append-Text([string]$Text) {
    if (-not $Text) { return }
    $script:LogBox.AppendText($Text + "`r`n")
    $script:LogBox.ScrollToEnd()
}

# ---------------------------------------------------------------- 加载构建（后台）
$script:LoadJob = $null
$script:LoadTimer = $null

function Start-LoadBuilds {
    $family = Get-SelectedTag $script:CmbFamily
    $arch = Get-SelectedTag $script:CmbArch
    if (-not $family -or -not $arch) { return }

    $script:BtnLoad.IsEnabled = $false
    $script:CmbBuild.Items.Clear()
    [void]$script:CmbBuild.Items.Add('正在查询 UUP ...')
    $script:CmbBuild.SelectedIndex = 0
    Set-Status '正在查询可用构建' '读取 UUP dump 接口（按代次分批，约 5-15 秒）'

    $root = $script:Root
    $script:LoadJob = Start-Job -ScriptBlock {
        param($RootArg, $Family, $Arch)
        $ErrorActionPreference = 'Stop'
        . (Join-Path $RootArg 'lib\common.ps1')
        . (Join-Path $RootArg 'lib\uup.ps1')
        try {
            $b = Get-UupBuilds -Family $Family -Arch $Arch
            return @($b | Select-Object Title, Uuid, Build, Arch, Created)
        } catch {
            return @{ Error = $_.Exception.Message }
        }
    } -ArgumentList $root, $family, $arch

    $script:LoadTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:LoadTimer.Interval = [TimeSpan]::FromMilliseconds(600)
    $script:LoadTimer.Add_Tick({
        if ($script:LoadJob.State -eq 'Running') { return }
        $script:LoadTimer.Stop()
        $res = @(Receive-Job -Job $script:LoadJob -ErrorAction SilentlyContinue)
        Remove-Job -Job $script:LoadJob -Force -ErrorAction SilentlyContinue
        $script:BtnLoad.IsEnabled = $true
        $script:CmbBuild.Items.Clear()

        if ($res.Count -ge 1 -and $res[0] -is [hashtable] -and $res[0].ContainsKey('Error')) {
            [void]$script:CmbBuild.Items.Add('查询失败：' + $res[0].Error)
            Set-Status '查询失败' $res[0].Error
            return
        }
        $builds = @($res | Where-Object { $_.Uuid })
        if ($builds.Count -eq 0) {
            [void]$script:CmbBuild.Items.Add('没有找到正式版构建')
            Set-Status '没有可用构建' ''
            return
        }
        foreach ($b in $builds) {
            [void]$script:CmbBuild.Items.Add((New-Object System.Windows.Controls.ComboBoxItem -Property @{
                Content = ($b.Title + '    ' + $b.Build + '    ' + $b.Created)
                Tag = $b.Uuid
            }))
        }
        $script:CmbBuild.SelectedIndex = 0
        Set-Status ('已加载 ' + $builds.Count + ' 个正式版构建') '选好语言和版本种类后即可开始'
        Set-Step 1
    })
    $script:LoadTimer.Start()
}

# ---------------------------------------------------------------- 语言 / 版本
$script:LangJob = $null
$script:LangTimer = $null

function Start-LoadLangs {
    $uuid = Get-SelectedTag $script:CmbBuild
    if (-not $uuid) { return }
    $script:CmbLang.Items.Clear()
    [void]$script:CmbLang.Items.Add('正在查询语言 ...')
    $script:CmbEdition.Items.Clear()
    Set-Status '正在查询语言' ''

    $root = $script:Root
    $script:LangJob = Start-Job -ScriptBlock {
        param($RootArg, $Uuid)
        $ErrorActionPreference = 'Stop'
        . (Join-Path $RootArg 'lib\common.ps1')
        . (Join-Path $RootArg 'lib\uup.ps1')
        try { return @(Get-LangChoices -Langs (Get-UupLangs -Uuid $Uuid)) }
        catch { return @{ Error = $_.Exception.Message } }
    } -ArgumentList $root, $uuid

    $script:LangTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:LangTimer.Interval = [TimeSpan]::FromMilliseconds(500)
    $script:LangTimer.Add_Tick({
        if ($script:LangJob.State -eq 'Running') { return }
        $script:LangTimer.Stop()
        $res = @(Receive-Job -Job $script:LangJob -ErrorAction SilentlyContinue)
        Remove-Job -Job $script:LangJob -Force -ErrorAction SilentlyContinue
        $script:CmbLang.Items.Clear()
        if ($res.Count -ge 1 -and $res[0] -is [hashtable] -and $res[0].ContainsKey('Error')) {
            [void]$script:CmbLang.Items.Add('查询失败：' + $res[0].Error)
            return
        }
        foreach ($l in $res) {
            [void]$script:CmbLang.Items.Add((New-Object System.Windows.Controls.ComboBoxItem -Property @{ Content = $l.Label; Tag = $l.Value }))
        }
        $idx = 0
        for ($i = 0; $i -lt $script:CmbLang.Items.Count; $i++) {
            if ($script:CmbLang.Items[$i].Tag -eq 'zh-cn') { $idx = $i; break }
        }
        $script:CmbLang.SelectedIndex = $idx
        Set-Status '语言已加载' '正在查询版本种类 ...'
    })
    $script:LangTimer.Start()
}

$script:EdJob = $null
$script:EdTimer = $null

function Start-LoadEditions {
    $uuid = Get-SelectedTag $script:CmbBuild
    $lang = Get-SelectedTag $script:CmbLang
    if (-not $uuid -or -not $lang) { return }
    $script:CmbEdition.Items.Clear()
    [void]$script:CmbEdition.Items.Add('正在查询版本 ...')

    $root = $script:Root
    $script:EdJob = Start-Job -ScriptBlock {
        param($RootArg, $Uuid, $Lang)
        $ErrorActionPreference = 'Stop'
        . (Join-Path $RootArg 'lib\common.ps1')
        . (Join-Path $RootArg 'lib\uup.ps1')
        try { return @(Get-UupEditions -Uuid $Uuid -Lang $Lang) }
        catch { return @{ Error = $_.Exception.Message } }
    } -ArgumentList $root, $uuid, $lang

    $script:EdTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:EdTimer.Interval = [TimeSpan]::FromMilliseconds(500)
    $script:EdTimer.Add_Tick({
        if ($script:EdJob.State -eq 'Running') { return }
        $script:EdTimer.Stop()
        $res = @(Receive-Job -Job $script:EdJob -ErrorAction SilentlyContinue)
        Remove-Job -Job $script:EdJob -Force -ErrorAction SilentlyContinue
        $script:CmbEdition.Items.Clear()
        if ($res.Count -ge 1 -and $res[0] -is [hashtable] -and $res[0].ContainsKey('Error')) {
            [void]$script:CmbEdition.Items.Add('查询失败：' + $res[0].Error)
            return
        }
        foreach ($e in $res) {
            [void]$script:CmbEdition.Items.Add((New-Object System.Windows.Controls.ComboBoxItem -Property @{
                Content = ($e.Name + '   [' + $e.Code + ']'); Tag = $e.Code
            }))
        }
        $script:CmbEdition.SelectedIndex = 0
        Set-Status '准备就绪' '检查右侧选项，然后点「开始生成」'
        Set-Step 2
    })
    $script:EdTimer.Start()
}

$script:BtnLoad.Add_Click({ Start-LoadBuilds })
$script:CmbBuild.Add_SelectionChanged({ if (Get-SelectedTag $script:CmbBuild) { Start-LoadLangs } })
$script:CmbLang.Add_SelectionChanged({ if (Get-SelectedTag $script:CmbLang) { Start-LoadEditions } })

$script:BtnWork.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = '选择工作目录（下载与转换用，需要 30 GB）'
    if ($dlg.ShowDialog() -eq 'OK') { $script:TxtWork.Text = $dlg.SelectedPath }
})
$script:BtnOut.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = '选择 ISO 输出目录'
    if ($dlg.ShowDialog() -eq 'OK') { $script:TxtOut.Text = $dlg.SelectedPath }
})

# ---------------------------------------------------------------- 统计选中
function Get-CheckedValues($Map) {
    $out = @()
    foreach ($k in $Map.Keys) { if ($Map[$k].IsChecked) { $out += $k } }
    return ,$out
}

# ---------------------------------------------------------------- 开始
$script:BtnStart.Add_Click({
    $uuid = Get-SelectedTag $script:CmbBuild
    $lang = Get-SelectedTag $script:CmbLang
    $edition = Get-SelectedTag $script:CmbEdition
    if (-not $uuid) { Append-Text '[!] 请先加载构建并选择一个'; return }
    if (-not $lang) { Append-Text '[!] 还没有选择语言'; return }
    if (-not $edition) { Append-Text '[!] 还没有选择版本种类'; return }

    $work = $script:TxtWork.Text.Trim()
    $outDir = $script:TxtOut.Text.Trim()
    if (-not $work -or -not $outDir) { Append-Text '[!] 工作目录 / 输出目录不能为空'; return }

    try {
        foreach ($p in @($work, $outDir)) { if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null } }
    } catch {
        Append-Text ('[!] 目录创建失败: ' + $_.Exception.Message); return
    }

    $free = Get-FreeSpaceGB $work
    if ($free -ge 0 -and $free -lt 25) {
        $disk = $(if ($work.Length -ge 2) { $work.Substring(0, 2) } else { $work })
        Append-Text ('[!] ' + $disk + ' 只剩 ' + $free + ' GB，建议换到空间更大的盘（需要约 30 GB）')
    }

    $ops = Get-CheckedValues $script:OpsChecks
    if ($ops.Count -eq 0) {
        # 一项都不勾是合法需求：只要官方原版 ISO，不做任何精简/美化/美化。
        # （旧逻辑在这里直接 return，等于用户永远做不出"纯原版"）
        Append-Text '[i] 未勾选任何操作：本次只生成/复制官方原版 ISO，不做精简与定制'
    }

    $beauty = @{ Theme = $(if ($script:RbLight.IsChecked) { 'light' } else { 'dark' }) }
    foreach ($k in $script:BeautyChecks.Keys) { $beauty[$k] = [bool]$script:BeautyChecks[$k].IsChecked }

    # 下拉项文本是 "标题    构建号    日期"，用正则按 2 个以上空格切，别用 Split('    ')
    # （Split 的字符串参数会被当成 char[]，等于按单个空格切，标题只剩 "Windows"）
    $buildTitle = (($script:CmbBuild.SelectedItem.Content.ToString()) -split '\s{4,}')[0].Trim()

    $param = [ordered]@{
        Family  = 'unknown'
        Arch    = (Get-SelectedTag $script:CmbArch)
        Uuid    = $uuid
        Title   = $buildTitle
        Lang    = $lang
        Edition = $edition
        Ops     = @($ops)
        Beauty  = $beauty
        WorkDir = $work
        OutDir  = $outDir
    }
    # 家族用于选精简清单：Server 用 server 清单
    $param.Family = Get-SelectedTag $script:CmbFamily

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $tmp = Join-Path $env:TEMP ('winiso_gui_' + $stamp)
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $jsonPath = Join-Path $tmp 'params.json'
    ($param | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $jsonPath -Encoding UTF8

    $script:LogFile = Join-Path $tmp 'run.log'
    $script:ReadOffset = 0
    Set-Content -LiteralPath $script:LogFile -Value '' -Encoding UTF8
    $script:ResultIso = $null
    $script:IdleTicks = 0

    $root = $script:Root
    $runCmd = Join-Path $tmp 'run.cmd'
    $lines = @(
        '@echo off',
        'chcp 65001 >nul',
        ('powershell -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $root 'winiso.ps1') + '" run "' + $jsonPath + '" >> "' + $script:LogFile + '" 2>&1'),
        ('echo WINISO_EXIT=%ERRORLEVEL% >> "' + $script:LogFile + '"')
    )
    # 文件名/路径里可能有中文（中文用户名时 %TEMP% 就是中文路径）。用 ASCII 写会把汉字变成 '?'，
    # run.cmd 里的 params.json 路径直接失效，管理员窗口一闪就关，日志永远是空的。
    # 所以：全 ASCII 才用 ASCII 编码；含中文改用 UTF-8 无 BOM（第一行已 chcp 65001）。
    $rn = ($lines -join "`r`n")
    $enc = [Text.Encoding]::ASCII
    if ($rn -match '[^\x00-\x7F]') { $enc = New-Object Text.UTF8Encoding($false) }
    [IO.File]::WriteAllText($runCmd, $rn, $enc)

    $script:LogBox.Text = ''
    Append-Text ('[>] 目标 ' + $buildTitle + ' / ' + $param.Arch + ' / ' + $lang + ' / ' + $edition)
    Append-Text ('[>] 操作 ' + ($ops -join ', '))
    Append-Text ('[>] 工作目录 ' + $work)
    Append-Text ('[>] 开始执行（管理员窗口，日志实时显示）...')
    Set-Status '正在生成...' '下载 7-8 GB，预计 60-120 分钟'
    try { $script:LogBox.BringIntoView() } catch { }
    Set-Step 3
    $script:BtnStart.IsEnabled = $false
    $script:BtnOpen.IsEnabled = $false

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = (Join-Path $env:SystemRoot 'System32\cmd.exe')
        $psi.Arguments = '/c "' + $runCmd + '"'
        $psi.Verb = 'runas'
        $psi.UseShellExecute = $true
        $psi.WindowStyle = 'Hidden'
        [void][System.Diagnostics.Process]::Start($psi)
    } catch {
        Append-Text ('[!] 启动失败（可能取消了 UAC）: ' + $_.Exception.Message)
        Set-Status '未启动' '需要管理员授权'
        $script:BtnStart.IsEnabled = $true
        return
    }

    $script:TailTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:TailTimer.Interval = [TimeSpan]::FromMilliseconds(900)
    $script:TailTimer.Add_Tick({
        if (-not $script:LogFile -or -not (Test-Path -LiteralPath $script:LogFile)) { return }
        $txt = $null
        try {
            $fs = [IO.File]::Open($script:LogFile, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
            try {
                $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)
                $txt = $sr.ReadToEnd()
                $sr.Dispose()
            } finally { $fs.Dispose() }
        } catch { return }
        if ($null -eq $txt) { return }
        if ($txt.Length -gt $script:ReadOffset) {
            $delta = $txt.Substring($script:ReadOffset)
            $script:ReadOffset = $txt.Length
            $script:LogBox.AppendText($delta)
            $script:LogBox.ScrollToEnd()
        }
        if ($txt -match 'WINISO_RESULT_ISO=(.+)') {
            $script:TailTimer.Stop()
            $script:ResultIso = $Matches[1].Trim()
            Set-Status '生成完成' $script:ResultIso
            $script:BtnStart.IsEnabled = $true
            $script:BtnOpen.IsEnabled = $true
            Set-Step 3
        } elseif ($txt -match 'WINISO_EXIT=([0-9]+)') {
            $code = [int]$Matches[1]
            $script:TailTimer.Stop()
            if ($code -ne 0) {
                Set-Status ('生成中断（退出码 ' + $code + '）') '日志里有具体原因，修好后可重跑续传'
            } else {
                # 退出码 0 但没看到 WINISO_RESULT_ISO：多半是"已经在输出目录里了"或标记行没被读到。
                # 旧代码在这种情况下什么都不做，按钮永久灰掉，只能关窗口重开。
                Set-Status '已结束' '没有捕获到 ISO 路径，去输出目录看看，或点"打开输出目录"'
                if ($script:TxtOut.Text.Trim() -and (Test-Path -LiteralPath $script:TxtOut.Text.Trim())) {
                    $hit = Get-ChildItem -LiteralPath $script:TxtOut.Text.Trim() -Filter '*.iso' -ErrorAction SilentlyContinue |
                           Sort-Object LastWriteTime -Descending | Select-Object -First 1
                    if ($hit) { $script:ResultIso = $hit.FullName; Set-Status '生成完成' $hit.FullName }
                }
            }
            $script:BtnStart.IsEnabled = $true
            $script:BtnOpen.IsEnabled = $true
        }
        if ($txt.Length -eq 0) {
            $script:IdleTicks++
            if ($script:IdleTicks -eq 60) {
                # 约 1 分钟还没有任何输出：要么 UAC 被取消，要么管理员窗口没能读到参数文件
                Set-Status '没有输出' '管理员窗口是否弹出来了？被拒的话重新点"开始生成"'
                $script:BtnStart.IsEnabled = $true
            }
        } else { $script:IdleTicks = 0 }
        if ($txt -match '下载进度') { Set-Step 3 }
        if ($txt -match '转换') { $script:TxtSub.Text = '正在合成映像并打包 ISO...' }
        if ($txt -match '精简') { $script:TxtSub.Text = '正在离线精简与定制...' }
    })
    $script:TailTimer.Start()
})

$script:BtnDiag.Add_Click({
    # 下载失败时点这个：开一个控制台窗口跑 winiso diag（脚本包 + 清单 + 抽样文件 + SHA1）
    $ps1 = Join-Path $script:Root 'winiso.ps1'
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', $ps1, 'diag')
})

$script:BtnOpen.Add_Click({
    $target = $script:TxtOut.Text.Trim()
    if ($script:ResultIso -and (Test-Path -LiteralPath $script:ResultIso)) {
        $target = Split-Path -Parent $script:ResultIso
    }
    if ($target -and (Test-Path -LiteralPath $target)) { Start-Process explorer.exe -ArgumentList ('"' + $target + '"') }
})

# 首屏：自动加载一次构建
$script:win.Add_Loaded({
    Set-Step 1
    Start-LoadBuilds
})

[void]$script:win.ShowDialog()
