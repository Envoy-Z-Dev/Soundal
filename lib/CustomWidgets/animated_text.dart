import 'package:flutter/material.dart';
import 'package:soundal/CustomWidgets/fading_edge_scrollview.dart';

class AnimatedText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final double? textScaleFactor;
  final TextDirection textDirection;
  final Axis scrollAxis;
  final CrossAxisAlignment crossAxisAlignment;
  final TextAlign defaultAlignment;
  final double blankSpace;
  final double velocity;
  final Duration startAfter;
  final Duration pauseAfterRound;
  final int? numberOfRounds;
  final bool showFadingOnlyWhenScrolling;
  final double fadingEdgeStartFraction;
  final double fadingEdgeEndFraction;
  final double startPadding;
  final Duration accelerationDuration;
  final Curve accelerationCurve;
  final Duration decelerationDuration;
  final Curve decelerationCurve;
  final VoidCallback? onDone;

  const AnimatedText({
    super.key,
    required this.text,
    this.style,
    this.textScaleFactor,
    this.textDirection = TextDirection.ltr,
    this.scrollAxis = Axis.horizontal,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.defaultAlignment = TextAlign.center,
    this.blankSpace = 0.0,
    this.velocity = 5,
    this.startAfter = Duration.zero,
    this.pauseAfterRound = Duration.zero,
    this.showFadingOnlyWhenScrolling = true,
    this.fadingEdgeStartFraction = 0.0,
    this.fadingEdgeEndFraction = 0.0,
    this.numberOfRounds,
    this.startPadding = 0.0,
    this.accelerationDuration = Duration.zero,
    this.accelerationCurve = Curves.decelerate,
    this.decelerationDuration = Duration.zero,
    this.decelerationCurve = Curves.decelerate,
    this.onDone,
  });

  @override
  _AnimatedTextState createState() => _AnimatedTextState();
}

class _AnimatedTextState extends State<AnimatedText>
    with SingleTickerProviderStateMixin {
  late ScrollController _scrollController;
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _animationController = AnimationController(
      vsync: this,
      duration:
          Duration(seconds: (widget.text.length / widget.velocity).ceil()),
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(_animationController);

    _animationController.addListener(() {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(
          _animation.value * _scrollController.position.maxScrollExtent,
        );
      }
    });

    _animationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (widget.numberOfRounds == null || widget.numberOfRounds! > 1) {
          _animationController.repeat();
        } else {
          widget.onDone?.call();
        }
      }
    });

    Future.delayed(widget.startAfter, () {
      _animationController.forward();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final span = TextSpan(
          text: widget.text,
          style: widget.style,
        );

        final tp = TextPainter(
          maxLines: 1,
          textAlign: TextAlign.left,
          textDirection: TextDirection.ltr,
          text: span,
        );

        tp.layout();

        if (tp.width > constraints.maxWidth) {
          final scrollingText = SingleChildScrollView(
            scrollDirection: widget.scrollAxis,
            controller: _scrollController,
            child: Container(
              padding: EdgeInsets.only(
                right: widget.scrollAxis == Axis.horizontal ? tp.width : 0,
                bottom: widget.scrollAxis == Axis.vertical ? tp.height : 0,
              ),
              child: Text(
                widget.text,
                style: widget.style,
                textScaleFactor: widget.textScaleFactor,
              ),
            ),
          );

          return SizedBox(
            width: constraints.maxWidth,
            height: tp.height,
            child: FadingEdgeScrollView.fromSingleChildScrollView(
              gradientFractionOnStart: widget.fadingEdgeStartFraction,
              gradientFractionOnEnd: widget.fadingEdgeEndFraction,
              child: scrollingText,
            ),
          );
        } else {
          return SizedBox(
            width: constraints.maxWidth,
            child: Text(
              widget.text,
              style: widget.style,
              textAlign: widget.defaultAlignment,
              textScaleFactor: widget.textScaleFactor,
            ),
          );
        }
      },
    );
  }
}
