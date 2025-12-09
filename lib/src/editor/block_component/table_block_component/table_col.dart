import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_action_handler.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_col_border.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_drag_data.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_row.dart';
import 'package:appflowy_editor/src/editor/util/platform_extension.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class TableCol extends StatefulWidget {
  const TableCol({
    super.key,
    required this.tableNode,
    required this.editorState,
    required this.colIdx,
    required this.tableStyle,
    required this.rowDragNotifier,
    required this.rowActionNotifier,
    required this.cellFocusNotifier,
    this.menuBuilder,
  });

  final int colIdx;
  final EditorState editorState;
  final TableNode tableNode;

  final TableBlockComponentMenuBuilder? menuBuilder;

  final TableStyle tableStyle;
  final TableRowDragNotifier rowDragNotifier;
  final TableRowActionNotifier rowActionNotifier;
  final TableCellFocusNotifier cellFocusNotifier;

  @override
  State<TableCol> createState() => _TableColState();
}

class _TableColState extends State<TableCol> {
  bool _colActionVisiblity = false;
  double? _cachedColWidth;

  Map<String, void Function()> listeners = {};

  double _getColWidth() {
    if (_cachedColWidth != null) {
      return _cachedColWidth!;
    }
    final width = widget.tableNode.getColWidth(widget.colIdx);
    _cachedColWidth = width;
    return width;
  }

  @override
  void didUpdateWidget(TableCol oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset cache when table node or column index changes
    if (oldWidget.tableNode != widget.tableNode || oldWidget.colIdx != widget.colIdx) {
      _cachedColWidth = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> children = [];
    if (widget.colIdx == 0) {
      children.add(
        Padding(
          padding: EdgeInsets.only(top: 10),
          child: TableColBorder(
            resizable: false,
            tableNode: widget.tableNode,
            editorState: widget.editorState,
            colIdx: widget.colIdx,
            borderColor: widget.tableStyle.borderColor,
            borderHoverColor: widget.tableStyle.borderHoverColor,
          ),
        ),
      );
    }

    children.addAll([
      DragTarget<TableDragData>(
        onWillAcceptWithDetails: (details) {
          return details.data.dir == TableDirection.col &&
              details.data.node == widget.tableNode.node &&
              details.data.position != widget.colIdx;
        },
        onAcceptWithDetails: (details) {
          TableActions.move(
            widget.tableNode.node,
            details.data.position,
            widget.colIdx,
            widget.editorState,
            TableDirection.col,
          );
        },
        builder: (context, candidateData, rejectedData) {
          final isHovering = candidateData.isNotEmpty;
          final draggedPosition = candidateData.isNotEmpty ? candidateData.first!.position : -1;
          final isMovingLeft = draggedPosition > widget.colIdx;

          return Stack(
            children: [
              SizedBox(
                width: _getColWidth(),
                child: Stack(
                  children: [
                    MouseRegion(
                      onEnter: (_) => setState(() => _colActionVisiblity = true),
                      onExit: (_) => setState(() => _colActionVisiblity = false),
                      child: Column(children: _buildCells(context)),
                    ),
                    ListenableBuilder(
                      listenable: widget.cellFocusNotifier,
                      builder: (context, child) {
                        final isFocused = widget.cellFocusNotifier.isColFocused(widget.colIdx);
                        // On mobile, show when cell is focused (selected)
                        // On desktop, show only on hover
                        final isMobile = PlatformExtension.isMobile;
                        final shouldShow = isMobile ? isFocused : _colActionVisiblity;
                        return TableActionHandler(
                          visible: shouldShow,
                          node: widget.tableNode.node,
                          editorState: widget.editorState,
                          position: widget.colIdx,
                          alignment: Alignment.topCenter,
                          menuBuilder: widget.menuBuilder,
                          dir: TableDirection.col,
                        );
                      },
                    ),
                  ],
                ),
              ),
              if (isHovering)
                Positioned(
                  left: isMovingLeft ? -2 : null,
                  right: isMovingLeft ? null : -2,
                  top: 10,
                  bottom: 0,
                  child: Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: widget.tableStyle.borderHoverColor,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: [
                        BoxShadow(
                          color: widget.tableStyle.borderHoverColor.withValues(alpha: 0.5),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      Padding(
        padding: EdgeInsets.only(top: 10),
        child: TableColBorder(
          resizable: true,
          tableNode: widget.tableNode,
          editorState: widget.editorState,
          colIdx: widget.colIdx,
          borderColor: widget.tableStyle.borderColor,
          borderHoverColor: widget.tableStyle.borderHoverColor,
        ),
      ),
    ]);

    return Row(children: children);
  }

  List<Widget> _buildCells(BuildContext context) {
    final rowsLen = widget.tableNode.rowsLen;
    final List<Widget> cells = [];
    final Widget cellBorder = Container(
      height: widget.tableNode.config.borderWidth,
      color: widget.tableStyle.borderColor,
    );

    for (var i = 0; i < rowsLen; i++) {
      final node = widget.tableNode.getCell(widget.colIdx, i);
      updateRowHeightCallback(i);
      addListener(node, i);

      // Only add listener to first child if it exists
      if (node.children.isNotEmpty) {
        addListener(node.children.first, i);
      }

      Widget cellWidget = widget.editorState.renderer.build(
        context,
        node,
      );

      // Wrap the cell with the row action notifier for hover detection
      cellWidget = _TableColWithRowActionNotifier(
        rowActionNotifier: widget.rowActionNotifier,
        cellFocusNotifier: widget.cellFocusNotifier,
        child: cellWidget,
      );

      // Wrap ALL cells with TableRowDragTarget so any cell can accept the drop
      cellWidget = TableRowDragTarget(
        tableNode: widget.tableNode.node,
        rowIdx: i,
        editorState: widget.editorState,
        dragNotifier: widget.rowDragNotifier,
        child: cellWidget,
      );

      // Add visual indicator line when row is hovered
      cellWidget = ListenableBuilder(
        listenable: widget.rowDragNotifier,
        builder: (context, child) {
          final isRowHovered = widget.rowDragNotifier.hoveredRow == i;

          // Get the dragged row position to determine direction
          final draggedRowPosition = widget.rowDragNotifier.draggedRowPosition;
          final isMovingUp = draggedRowPosition != null && draggedRowPosition > i;

          return Stack(
            children: [
              child!,
              if (isRowHovered)
                Positioned(
                  left: 0,
                  right: 0,
                  top: isMovingUp ? -2 : null,
                  bottom: isMovingUp ? null : -2,
                  child: IgnorePointer(
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: widget.tableStyle.borderHoverColor,
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: [
                          BoxShadow(
                            color: widget.tableStyle.borderHoverColor.withValues(alpha: 0.5),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
        child: cellWidget,
      );

      cells.addAll([
        cellWidget,
        cellBorder,
      ]);
    }

    return [
      Padding(
        padding: EdgeInsets.only(top: 10),
        child: Column(children: [
          cellBorder,
          ...cells,
        ]),
      ),
    ];
  }

  void addListener(Node node, int row) {
    if (listeners.containsKey(node.id)) {
      return;
    }

    listeners[node.id] = () => updateRowHeightCallback(row);
    node.addListener(listeners[node.id]!);
  }

  void updateRowHeightCallback(int row) => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (row >= widget.tableNode.rowsLen) {
          return;
        }

        // Reset cached width when row height changes as it might affect column layout
        _cachedColWidth = null;

        final transaction = widget.editorState.transaction;
        widget.tableNode.updateRowHeight(
          row,
          editorState: widget.editorState,
          transaction: transaction,
        );
        if (transaction.operations.isNotEmpty) {
          transaction.afterSelection = transaction.beforeSelection;
          widget.editorState.apply(transaction);
        }
      });
}

class _TableColWithRowActionNotifier extends StatelessWidget {
  const _TableColWithRowActionNotifier({
    required this.rowActionNotifier,
    required this.cellFocusNotifier,
    required this.child,
  });

  final TableRowActionNotifier rowActionNotifier;
  final TableCellFocusNotifier cellFocusNotifier;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<TableRowActionNotifier>.value(
          value: rowActionNotifier,
        ),
        ChangeNotifierProvider<TableCellFocusNotifier>.value(
          value: cellFocusNotifier,
        ),
      ],
      child: child,
    );
  }
}
