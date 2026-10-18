import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math' as math;

import 'dashboard_screen.dart';
import 'login_screen.dart';

class InitialBootScreen extends StatefulWidget {
  // 🟢 追記：設定画面から呼び出されたかどうかを判定するフラグ
  final bool isFromSettings;
  const InitialBootScreen({super.key, this.isFromSettings = false});

  @override
  State<InitialBootScreen> createState() => _InitialBootScreenState();
}

class _InitialBootScreenState extends State<InitialBootScreen> with TickerProviderStateMixin {
  final PageController _pageController = PageController(initialPage: 0);
  int _currentPage = 0;

  late AnimationController _spinController;
  late AnimationController _swipeController;
  late AnimationController _timeTableController;
  late AnimationController _silentCameraController;
  late AnimationController _blinkController;

  late Animation<double> _slideAnim;
  late Animation<double> _pointerOpacityAnim;
  late Animation<double> _swipeOutAnim;
  late Animation<double> _expandAnim;
  late Animation<double> _ttPointerOpacityAnim;
  late Animation<double> _swipeRightAnim;
  late Animation<double> _expandRightAnim;
  late Animation<double> _scPointerOpacityAnim;

  // 🟢 データを動的に生成するため late に変更
  late List<Map<String, dynamic>> _onboardingData;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // 🟢 変更：設定画面からの呼び出し時でも、通常の4枚目と同じテキストにする
    _onboardingData = [
      {}, // 0: Welcome用
      {
        "title": "Daily Task",
        "description": "予定/課題を一覧表示",
      },
      {
        "title": "Time Table",
        "description": "時間割と授業一覧\nホーム画面を左にスワイプ",
      },
      {
        "title": "Silent Camera/Memo",
        "description": "瞬時にメモを残す\nホーム画面を右スワイプでカメラメモ起動",
      },
      {
        "title": "Login",
        "description": "右下のボタンからログイン/リロード",
      },
    ];

    _spinController = AnimationController(vsync: this, duration: const Duration(seconds: 20))..repeat();

    // ... 以下はそのまま

    _swipeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2500));
    _slideAnim = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _swipeController, curve: const Interval(0.2, 0.6, curve: Curves.easeInOut)));
    _pointerOpacityAnim = TweenSequence([
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: 1.0), weight: 10),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.0), weight: 60),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 0.0), weight: 10),
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: 0.0), weight: 20),
    ]).animate(_swipeController);

    _timeTableController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2500));
    _swipeOutAnim = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _timeTableController, curve: const Interval(0.2, 0.6, curve: Curves.easeInOutCubic)));
    _expandAnim = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _timeTableController, curve: const Interval(0.2, 0.6, curve: Curves.easeInOutCubic)));
    _ttPointerOpacityAnim = TweenSequence([
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: 1.0), weight: 10),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.0), weight: 50),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 0.0), weight: 10),
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: 0.0), weight: 30),
    ]).animate(_timeTableController);

    _silentCameraController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2500));
    _swipeRightAnim = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _silentCameraController, curve: const Interval(0.2, 0.6, curve: Curves.easeInOutCubic)));
    _expandRightAnim = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _silentCameraController, curve: const Interval(0.2, 0.6, curve: Curves.easeInOutCubic)));
    _scPointerOpacityAnim = TweenSequence([
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: 1.0), weight: 10),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.0), weight: 50),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 0.0), weight: 10),
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: 0.0), weight: 30),
    ]).animate(_silentCameraController);

    _blinkController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  }

  @override
  void dispose() {
    _spinController.dispose();
    _swipeController.dispose();
    _timeTableController.dispose();
    _silentCameraController.dispose();
    _blinkController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finishOnboarding() async {
    _spinController.stop();
    _swipeController.stop();
    _timeTableController.stop();
    _silentCameraController.stop();
    _blinkController.stop();

    if (!mounted) return;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    // 🟢 設定画面からの呼び出しなら、設定画面に戻るだけ
    if (widget.isFromSettings) {
      Navigator.of(context).pop();
      return;
    }

    // 🟢 通常の初回起動なら、完了フラグを折ってログイン画面へ
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_shown_initial_boot_v1', false);

    await Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 800),
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: OktaLoginScreen(
              onLoginSuccess: () {},
            ),
          );
        },
      ),
    );

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(opacity: animation, child: const MainSkeleton());
        },
      ),
    );
  }

  void _handlePageChanged(int index) {
    setState(() {
      _currentPage = index;
    });

    _spinController.stop();
    _swipeController.stop();
    _timeTableController.stop();
    _silentCameraController.stop();
    _blinkController.stop();
    _blinkController.value = 0.0;

    if (index == 0) _spinController.repeat();
    else if (index == 1) _swipeController.repeat();
    else if (index == 2) _timeTableController.repeat();
    else if (index == 3) _silentCameraController.repeat();
    else if (index == 4) _blinkController.repeat(reverse: true); // 🟢 変更：条件を外し、常に点滅を開始させる
  }

  void _nextPage() {
    if (_currentPage < _onboardingData.length - 1) {
      _pageController.nextPage(duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
    } else {
      _finishOnboarding();
    }
  }

  Widget _buildGradientBox(double width, double height, double cornerRadius) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF73a0fe), Color(0xFF96a9f9), Color(0xFFf6c0e7)],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(cornerRadius),
          bottomRight: Radius.circular(cornerRadius),
        ),
      ),
    );
  }

  Widget _buildBottomButtons(double mockHeight, double innerSpacing, double buttonSize, double capsuleWidth, Color elementColor, {double offsetX = 0.0}) {
    return Positioned(
      bottom: mockHeight * 0.04,
      left: innerSpacing + offsetX,
      right: innerSpacing - offsetX,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(width: buttonSize, height: buttonSize, decoration: BoxDecoration(color: elementColor, shape: BoxShape.circle)),
          Container(width: capsuleWidth, height: buttonSize, decoration: BoxDecoration(color: elementColor, borderRadius: BorderRadius.circular(buttonSize / 2))),
          // 🟢 変更：設定画面からの呼び出し時でも、赤く点滅させる
          AnimatedBuilder(
              animation: _blinkController,
              builder: (context, child) {
                Color currentCircleColor = Color.lerp(elementColor, const Color(0xFFD0312D), _blinkController.value) ?? elementColor;
                return Container(width: buttonSize, height: buttonSize, decoration: BoxDecoration(color: currentCircleColor, shape: BoxShape.circle));
              }
          ),
        ],
      ),
    );
  }

  Widget _buildMockScreen(BuildContext context, bool isDark, int index) {
    Color bezelColor = isDark ? const Color(0xFF333333) : const Color(0xFFE0E0E0);
    Color screenBgColor = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF5F5F7);
    Color elementColor = isDark ? const Color(0xFF3A3A3C) : const Color(0xFFD1D1D6);

    double borderWidth = 3.0;

    return LayoutBuilder(
        builder: (context, constraints) {
          double mockHeight = constraints.maxHeight * 0.9;
          double mockWidth = mockHeight / 2.1;

          if (mockWidth > constraints.maxWidth * 0.9) {
            mockWidth = constraints.maxWidth * 0.9;
            mockHeight = mockWidth * 2.1;
          }

          double gradHeight = mockHeight * 0.38;
          double innerSpacing = mockWidth * 0.08;
          double buttonSize = mockWidth * 0.15;
          double capsuleWidth = mockWidth * 0.5;
          double cornerRadius = mockWidth * 0.15;

          Widget innerContent;

          if (index == 1) {
            innerContent = AnimatedBuilder(
              animation: _swipeController,
              builder: (context, child) {
                return Stack(
                  children: [
                    Positioned(
                      top: gradHeight + (mockHeight * 0.08), left: innerSpacing, right: innerSpacing,
                      child: Container(
                        height: gradHeight - (mockWidth * 0.06),
                        decoration: BoxDecoration(color: elementColor, borderRadius: BorderRadius.circular(mockWidth * 0.06)),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      left: -_slideAnim.value * mockWidth,
                      child: Row(
                        children: [
                          _buildGradientBox(mockWidth, gradHeight, mockWidth * 0.08),
                          _buildGradientBox(mockWidth, gradHeight, mockWidth * 0.08),
                        ],
                      ),
                    ),
                    _buildBottomButtons(mockHeight, innerSpacing, buttonSize, capsuleWidth, elementColor),
                    Positioned(
                      top: gradHeight / 2 - (mockWidth * 0.1),
                      left: (mockWidth * 0.6) - (_slideAnim.value * mockWidth * 0.4),
                      child: Opacity(
                        opacity: _pointerOpacityAnim.value,
                        child: Container(width: mockWidth * 0.2, height: mockWidth * 0.2, decoration: BoxDecoration(color: const Color(0xFFD0312D).withOpacity(0.6), shape: BoxShape.circle)),
                      ),
                    ),
                  ],
                );
              },
            );
          } else if (index == 2) {
            innerContent = AnimatedBuilder(
              animation: _timeTableController,
              builder: (context, child) {
                double swipeOffset = _swipeOutAnim.value * mockWidth;

                double middleBoxTop = gradHeight + (mockHeight * 0.08);
                double middleBoxHeight = gradHeight - (mockWidth * 0.06);
                double expandedHeight = gradHeight + (_expandAnim.value * ((middleBoxTop + middleBoxHeight) - gradHeight));

                return Stack(
                  children: [
                    Positioned(
                      top: middleBoxTop,
                      left: innerSpacing - swipeOffset,
                      child: Container(
                        width: mockWidth - (innerSpacing * 2),
                        height: middleBoxHeight,
                        decoration: BoxDecoration(color: elementColor, borderRadius: BorderRadius.circular(mockWidth * 0.06)),
                      ),
                    ),
                    Positioned(
                      top: 0, left: 0, right: 0,
                      child: _buildGradientBox(mockWidth, expandedHeight, mockWidth * 0.08),
                    ),
                    _buildBottomButtons(mockHeight, innerSpacing, buttonSize, capsuleWidth, elementColor),
                    Positioned(
                      top: middleBoxTop + (middleBoxHeight / 2) - (mockWidth * 0.1),
                      left: (mockWidth * 0.6) - swipeOffset,
                      child: Opacity(
                        opacity: _ttPointerOpacityAnim.value,
                        child: Container(width: mockWidth * 0.2, height: mockWidth * 0.2, decoration: BoxDecoration(color: const Color(0xFFD0312D).withOpacity(0.6), shape: BoxShape.circle)),
                      ),
                    ),
                  ],
                );
              },
            );
          } else if (index == 3) {
            innerContent = AnimatedBuilder(
              animation: _silentCameraController,
              builder: (context, child) {
                double swipeOffset = _swipeRightAnim.value * mockWidth;
                double middleBoxTop = gradHeight + (mockHeight * 0.08);
                double middleBoxHeight = gradHeight - (mockWidth * 0.06);
                double expandedHeight = gradHeight + (_expandRightAnim.value * ((middleBoxTop + middleBoxHeight) - gradHeight));

                return Stack(
                  children: [
                    Positioned(
                      top: middleBoxTop,
                      left: innerSpacing + swipeOffset,
                      child: Container(
                        width: mockWidth - (innerSpacing * 2),
                        height: middleBoxHeight,
                        decoration: BoxDecoration(color: elementColor, borderRadius: BorderRadius.circular(mockWidth * 0.06)),
                      ),
                    ),
                    _buildBottomButtons(mockHeight, innerSpacing, buttonSize, capsuleWidth, elementColor, offsetX: swipeOffset),
                    Positioned(
                      top: 0, left: 0, right: 0,
                      child: SizedBox(
                        height: expandedHeight,
                        child: Stack(
                          children: [
                            _buildGradientBox(mockWidth, expandedHeight, mockWidth * 0.08),
                            Positioned(
                              top: 6.0, bottom: 6.0, left: 6.0, right: 6.0,
                              child: Opacity(
                                opacity: _expandRightAnim.value,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black,
                                    borderRadius: BorderRadius.circular((mockWidth * 0.08) - 2.0),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: middleBoxTop + (middleBoxHeight / 2) - (mockWidth * 0.1),
                      left: (mockWidth * 0.4) + swipeOffset,
                      child: Opacity(
                        opacity: _scPointerOpacityAnim.value,
                        child: Container(width: mockWidth * 0.2, height: mockWidth * 0.2, decoration: BoxDecoration(color: const Color(0xFFD0312D).withOpacity(0.6), shape: BoxShape.circle)),
                      ),
                    ),
                  ],
                );
              },
            );
          } else {
            innerContent = Stack(
              children: [
                Positioned(
                  top: gradHeight + (mockHeight * 0.08), left: innerSpacing, right: innerSpacing,
                  child: Container(
                    height: gradHeight - (mockWidth * 0.06),
                    decoration: BoxDecoration(color: elementColor, borderRadius: BorderRadius.circular(mockWidth * 0.06)),
                  ),
                ),
                Positioned(
                  top: 0, left: 0, right: 0,
                  child: _buildGradientBox(mockWidth, gradHeight, mockWidth * 0.08),
                ),
                _buildBottomButtons(mockHeight, innerSpacing, buttonSize, capsuleWidth, elementColor),
              ],
            );
          }

          return Container(
            width: mockWidth,
            height: mockHeight,
            decoration: BoxDecoration(
              color: screenBgColor,
              borderRadius: BorderRadius.circular(cornerRadius),
              border: Border.all(color: bezelColor, width: borderWidth),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(cornerRadius - borderWidth),
              child: SizedBox(width: mockWidth, height: mockHeight, child: innerContent),
            ),
          );
        }
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color elementColor = isDark ? const Color(0xFF121212) : Colors.white;
    Color textColor = isDark ? Colors.white : Colors.black;

    Color btnColor;
    Border? btnBorder;
    Widget btnContent;

    if (_currentPage == 0) {
      btnColor = Colors.transparent;
      btnBorder = Border.all(color: Colors.white, width: 1.5);
      btnContent = const Text("Next", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold));
    } else if (_currentPage == _onboardingData.length - 1) {
      // 🟢 設定画面からの呼び出し時は、赤カプセルではなく通常のNextボタン（Done）にする
      if (widget.isFromSettings) {
        btnColor = elementColor;
        btnBorder = null;
        btnContent = Text("Done", style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold));
      } else {
        btnColor = const Color(0xFFD0312D);
        btnBorder = null;
        btnContent = const Icon(Icons.login_rounded, color: Colors.white, size: 22);
      }
    } else {
      btnColor = elementColor;
      btnBorder = null;
      btnContent = Text("Next", style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold));
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFFf6c0e7), Color(0xFF96a9f9), Color(0xFF73a0fe)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: _handlePageChanged,
                  itemCount: _onboardingData.length,
                  physics: const BouncingScrollPhysics(),
                  itemBuilder: (context, index) {

                    if (index == 0) {
                      return Stack(
                        children: [
                          Center(
                            child: AnimatedBuilder(
                              animation: _spinController,
                              builder: (context, child) {
                                return Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Transform.rotate(angle: _spinController.value * 2 * math.pi, child: Container(width: 1.0, height: 280, color: Colors.white)),
                                    Transform.rotate(angle: -_spinController.value * 1.4 * math.pi + (math.pi / 4), child: Container(width: 1.0, height: 280, color: Colors.white)),
                                  ],
                                );
                              },
                            ),
                          ),
                          const Align(
                            alignment: Alignment.bottomLeft,
                            child: Padding(
                              padding: EdgeInsets.only(left: 24.0, bottom: 0.0),
                              child: Text("Welcome\nto Dot Apps", style: TextStyle(color: Colors.white, fontSize: 52, fontWeight: FontWeight.w200, letterSpacing: 0.0, height: 1.05)),
                            ),
                          ),
                        ],
                      );
                    }

                    final data = _onboardingData[index];
                    return Padding(
                      padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 24.0, bottom: 16.0),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
                        decoration: BoxDecoration(color: elementColor, borderRadius: BorderRadius.circular(48)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Center(
                                child: _buildMockScreen(context, isDark, index),
                              ),
                            ),

                            const SizedBox(height: 32),

                            Text(
                              data["title"],
                              style: TextStyle(color: textColor, fontSize: 32, fontWeight: FontWeight.w200, letterSpacing: 0.0),
                              textAlign: TextAlign.left,
                            ),
                            const SizedBox(height: 12),

                            Text(
                              data["description"],
                              style: TextStyle(color: textColor.withOpacity(0.8), fontSize: 18, fontWeight: FontWeight.w400, height: 1.6),
                              textAlign: TextAlign.left,
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              Padding(
                padding: const EdgeInsets.only(left: 24.0, right: 24.0, bottom: 32.0, top: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _currentPage == 0
                        ? TextButton(
                      onPressed: () async {
                        final Uri url = Uri.parse('https://sites.google.com/view/kportal-app/english#h.c6csp7my3tz7');
                        if (await canLaunchUrl(url)) await launchUrl(url);
                      },
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                      child: const Text("Terms of Use", style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w300)),
                    )
                        : Padding(
                      padding: const EdgeInsets.only(bottom: 12.0, left: 8.0),
                      child: Text(
                        "$_currentPage/4",
                        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w200, letterSpacing: 2.0),
                      ),
                    ),

                    GestureDetector(
                      onTap: _nextPage,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.symmetric(horizontal: 36.0, vertical: 16.0),
                        decoration: BoxDecoration(color: btnColor, border: btnBorder, borderRadius: BorderRadius.circular(30)),
                        child: btnContent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}