import 'dart:developer' as developer;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/base_component/selection/selection_area_painter.dart';
import 'package:appflowy_editor/src/render/selection/cursor.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

final _deepEqual = const DeepCollectionEquality().equals;

class RemoteBlockSelectionsArea extends StatelessWidget {
  const RemoteBlockSelectionsArea({
    super.key,
    required this.node,
    required this.delegate,
    required this.remoteSelections,
    this.supportTypes = const [
      BlockSelectionType.cursor,
      BlockSelectionType.selection,
    ],
  });

  // get the cursor rect or selection rects from the delegate
  final SelectableMixin delegate;

  final ValueListenable<List<RemoteSelection>> remoteSelections;

  // the node of the block
  final Node node;

  final List<BlockSelectionType> supportTypes;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: remoteSelections,
      builder: (_, value, child) {
        child ??= const SizedBox.shrink();
        final selections = value.where((e) {
          final isIn = node.inSelection(e.selection.normalized);
          developer.log(
              'CursorDebug: Filter check for ${e.id}. Node: ${node.path}, Sel: ${e.selection.start.path}. In? $isIn');
          return isIn;
        }).toList();

        developer.log('CursorDebug: Selections for node ${node.id} (path ${node.path}): ${selections.length}');

        if (selections.isEmpty) {
          return child;
        }
        return Positioned.fill(
          child: Stack(
            children: selections
                .map(
                  (e) => RemoteBlockSelectionArea(
                    key: ValueKey(e.id),
                    node: node,
                    delegate: delegate,
                    remoteSelection: e,
                    supportTypes: supportTypes,
                  ),
                )
                .toList(),
          ),
        );
      },
      child: const SizedBox.shrink(),
    );
  }
}

/// [RemoteBlockSelectionArea] is a widget that renders the selection area or the cursor of a block from remote.
class RemoteBlockSelectionArea extends StatefulWidget {
  const RemoteBlockSelectionArea({
    super.key,
    required this.node,
    required this.delegate,
    required this.remoteSelection,
    this.supportTypes = const [
      BlockSelectionType.cursor,
      BlockSelectionType.selection,
    ],
  });

  // get the cursor rect or selection rects from the delegate
  final SelectableMixin delegate;

  final RemoteSelection remoteSelection;

  // the node of the block
  final Node node;

  final List<BlockSelectionType> supportTypes;

  @override
  State<RemoteBlockSelectionArea> createState() => _RemoteBlockSelectionAreaState();
}

class _RemoteBlockSelectionAreaState extends State<RemoteBlockSelectionArea> {
  // keep the previous cursor rect to avoid unnecessary rebuild
  Rect? prevCursorRect;
  // keep the previous selection rects to avoid unnecessary rebuild
  List<Rect>? prevSelectionRects;
  // keep the block selection rect to avoid unnecessary rebuild
  Rect? prevBlockRect;

  @override
  void initState() {
    super.initState();
    developer.log('CursorDebug: initState for ${widget.remoteSelection.id}');
    // Try to initialize rect immediately if possible to avoid blinking on first frame
    _updateSelectionIfNeeded(initial: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateSelectionIfNeeded();
    });
  }

  @override
  void dispose() {
    developer.log('CursorDebug: dispose for ${widget.remoteSelection.id}');
    super.dispose();
  }

  @override
  void didUpdateWidget(RemoteBlockSelectionArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    developer.log('CursorDebug: didUpdateWidget for ${widget.remoteSelection.id}');
  }

  @override
  Widget build(BuildContext context) {
    const child = SizedBox.shrink();
    final selection = widget.remoteSelection.selection;
    if (selection.isCollapsed) {
      // show the cursor when the selection is collapsed
      if (!widget.supportTypes.contains(BlockSelectionType.cursor) || prevCursorRect == null) {
        return child;
      }
      const shouldBlink = false;
      final cursor = Stack(
        clipBehavior: Clip.none,
        children: [
          Cursor(
            rect: prevCursorRect!,
            shouldBlink: shouldBlink,
            cursorStyle: widget.delegate.cursorStyle,
            color: widget.remoteSelection.cursorColor,
          ),
          widget.remoteSelection.builder?.call(
                context,
                widget.remoteSelection,
                prevCursorRect!,
              ) ??
              child,
        ],
      );
      return cursor;
    } else {
      // show the selection area when the selection is not collapsed
      if (!widget.supportTypes.contains(BlockSelectionType.selection) ||
          prevSelectionRects == null ||
          prevSelectionRects!.isEmpty ||
          (prevSelectionRects!.length == 1 && prevSelectionRects!.first.width == 0)) {
        return child;
      }
      return Stack(
        clipBehavior: Clip.none,
        children: [
          SelectionAreaPaint(
            rects: prevSelectionRects!,
            selectionColor: widget.remoteSelection.selectionColor,
          ),
          if (selection.start.path.equals(widget.node.path))
            widget.remoteSelection.builder?.call(
                  context,
                  widget.remoteSelection,
                  prevSelectionRects!.first,
                ) ??
                child,
        ],
      );
    }
  }

  void _updateSelectionIfNeeded({bool initial = false}) {
    if (!mounted) {
      return;
    }

    final selection = widget.remoteSelection.selection.normalized;
    final path = widget.node.path;

    // the current path is in the selection
    final isInSelection = path.inSelection(selection);
    if (isInSelection) {
      if (widget.supportTypes.contains(BlockSelectionType.cursor) && selection.isCollapsed) {
        final rect = widget.delegate.getCursorRectInPosition(selection.start);

        if (rect == null) {
          developer.log('CursorDebug: getCursorRectInPosition returned null. Ignoring update to prevent blink.');
          // Do not update state. Keep previous valid rect.
          // This handles cases where layout is dirty during text updates.
        } else if (rect != prevCursorRect) {
          if (initial) {
            prevCursorRect = rect;
            prevBlockRect = null;
            prevSelectionRects = null;
          } else {
            setState(() {
              prevCursorRect = rect;
              prevBlockRect = null;
              prevSelectionRects = null;
            });
          }
        }
      } else if (widget.supportTypes.contains(BlockSelectionType.selection)) {
        final rects = widget.delegate.getRectsInSelection(selection);
        if (!_deepEqual(rects, prevSelectionRects)) {
          if (initial) {
            prevSelectionRects = rects;
            prevCursorRect = null;
            prevBlockRect = null;
          } else {
            setState(() {
              prevSelectionRects = rects;
              prevCursorRect = null;
              prevBlockRect = null;
            });
          }
        }
      }
    } else if (prevBlockRect != null || prevSelectionRects != null || prevCursorRect != null) {
      developer.log('CursorDebug: Setting NULL because inSelection=false. Node: $path, Sel: ${selection.start.path}');
      if (initial) {
        prevBlockRect = null;
        prevSelectionRects = null;
        prevCursorRect = null;
      } else {
        setState(() {
          prevBlockRect = null;
          prevSelectionRects = null;
          prevCursorRect = null;
        });
      }
    }

    // Only schedule next frame if not initial (to avoid double scheduling logic, though initial calls postframe too)
    if (!initial) {
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
        _updateSelectionIfNeeded();
      });
    }
  }
}
