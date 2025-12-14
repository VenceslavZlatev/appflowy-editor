import 'dart:async';
import 'dart:io';

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
    required this.colResizeHoverNotifier,
    this.menuBuilder,
    this.scrollController,
  });

  final int colIdx;
  final EditorState editorState;
  final TableNode tableNode;

  final TableBlockComponentMenuBuilder? menuBuilder;

  final TableStyle tableStyle;
  final TableRowDragNotifier rowDragNotifier;
  final TableRowActionNotifier rowActionNotifier;
  final TableCellFocusNotifier cellFocusNotifier;
  final ValueNotifier<int?> colResizeHoverNotifier;
  final ScrollController? scrollController;

  @override
  State<TableCol> createState() => _TableColState();
}

class _TableColState extends State<TableCol> {
  bool _colActionVisiblity = false;
  double? _cachedColWidth;

  Map<String, void Function()> listeners = {};
  // Store node references for proper cleanup
  final Map<String, Node> _listenerNodes = {};

  // Debounce timer for row height updates to prevent excessive transactions
  Timer? _rowHeightUpdateTimer;
  final Set<int> _pendingRowHeightUpdates = {};

  // Track which rows have been initialized to avoid redundant listener setup
  // Track which rows have been initialized to avoid redundant listener setup
  final Set<String> _initializedCellNodes = {};

  OverlayEntry? _overlayEntry;
  final Map<int, LayerLink> _layerLinks = {};

  // LayerLinks for cell handles (key: rowIndex)
  final Map<int, LayerLink> _cellLayerLinks = {};

  // Track if the left part of the table is visible (for row handle visibility)
  final ValueNotifier<bool> _isLeftPartVisibleNotifier = ValueNotifier<bool>(true);

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
    // Update scroll listener if controller changed
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController?.removeListener(_onScrollChanged);
      widget.scrollController?.addListener(_onScrollChanged);
      _updateLeftPartVisibility();
    }
    // Reset cache when table node or column index changes
    if (oldWidget.tableNode != widget.tableNode || oldWidget.colIdx != widget.colIdx) {
      _cachedColWidth = null;
      // Clean up listeners for old nodes
      _cleanupListeners();
      _initializedCellNodes.clear();
      // Rebuild overlay if needed
      if (widget.colIdx == 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _updateOverlay();
        });
      }
      // Rebuild cell handles overlay for all columns
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateCellHandlesOverlay();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    // Listen to scroll changes to determine if left part is visible
    widget.scrollController?.addListener(_onScrollChanged);
    _updateLeftPartVisibility();
    if (widget.colIdx == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateOverlay();
      });
    }
    // Initialize cell handles overlay for all columns
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateCellHandlesOverlay();
    });
  }

  void _onScrollChanged() {
    _updateLeftPartVisibility();
  }

  void _updateLeftPartVisibility() {
    bool isVisible;
    if (widget.scrollController == null || !widget.scrollController!.hasClients) {
      isVisible = true;
    } else {
      // The handle is positioned at offset -10 from the first column
      // Since the table has left padding of 10, the handle is at the very left edge
      // We consider it visible if scroll offset is <= 0 (or within a small threshold)
      isVisible = widget.scrollController!.offset <= 0;
    }
    if (_isLeftPartVisibleNotifier.value != isVisible) {
      _isLeftPartVisibleNotifier.value = isVisible;
    }
  }

  OverlayEntry? _cellHandlesOverlayEntry;

  @override
  void dispose() {
    widget.scrollController?.removeListener(_onScrollChanged);
    _isLeftPartVisibleNotifier.dispose();
    _removeOverlay();
    _removeCellHandlesOverlay();
    _rowHeightUpdateTimer?.cancel();
    _cleanupListeners();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _removeCellHandlesOverlay() {
    _cellHandlesOverlayEntry?.remove();
    _cellHandlesOverlayEntry = null;
  }

  void _updateOverlay() {
    if (widget.colIdx != 0) return;

    _removeOverlay();

    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // We might need to listen to something to rebuild the overlay?
          // Actually, the OverlayEntry builder is called when overlay rebuilds.
          // But we need it to rebuild when rowActionNotifier changes.
          // So we wrap the whole stack in ListenableBuilder.
          ListenableBuilder(
            listenable:
                Listenable.merge([widget.rowActionNotifier, widget.cellFocusNotifier, _isLeftPartVisibleNotifier]),
            builder: (context, _) {
              return Stack(
                children: List.generate(widget.tableNode.rowsLen, (index) {
                  // Ensure we have a link for this row
                  if (!_layerLinks.containsKey(index)) return const SizedBox.shrink();

                  final isHovered = widget.rowActionNotifier.hoveredRowIndex == index;
                  final isFocused = widget.cellFocusNotifier.isRowFocused(index);
                  final isMobile = PlatformExtension.isMobile;
                  final shouldShow = (isMobile ? isFocused : isHovered) && _isLeftPartVisibleNotifier.value;

                  // If not visible, we can save performance by not rendering the handler?
                  // But we need to keep it in tree if it has state. TableActionHandler has state.
                  // However, visibility handles that.

                  return Positioned(
                    width: 20, // Arbitrary width for the handle area
                    child: CompositedTransformFollower(
                      link: _layerLinks[index]!,
                      showWhenUnlinked: false,
                      offset: const Offset(-10, 5), // Shift to the left gutter
                      child: TableActionHandler(
                        visible: shouldShow,
                        node: widget.tableNode.node,
                        editorState: widget.editorState,
                        position: index,
                        alignment: Alignment.centerLeft, // Align vertical center of cell
                        height: null, // Let it adapt
                        menuBuilder: widget.menuBuilder,
                        dir: TableDirection.row,
                      ),
                    ),
                  );
                }),
              );
            },
          ),
        ],
      ),
    );

    overlay.insert(_overlayEntry!);
  }

  void _updateCellHandlesOverlay() {
    _removeCellHandlesOverlay();

    final overlay = Overlay.of(context);
    _cellHandlesOverlayEntry = OverlayEntry(
      builder: (context) => ListenableBuilder(
        listenable: widget.cellFocusNotifier,
        builder: (context, _) {
          final focusedRow = widget.cellFocusNotifier.focusedRowIndex;
          final focusedCol = widget.cellFocusNotifier.focusedColIndex;

          // Only show handle if this column is focused
          if (focusedCol != widget.colIdx || focusedRow == null) {
            return const SizedBox.shrink();
          }

          // Ensure we have a link for this cell
          if (!_cellLayerLinks.containsKey(focusedRow)) {
            return const SizedBox.shrink();
          }

          // Get the cell height to center the handle vertically
          final cellHeight = widget.tableNode.getRowHeight(focusedRow);
          final colWidth = _getColWidth();

          return Positioned(
            width: 20, // Match the row handle width
            child: CompositedTransformFollower(
              link: _cellLayerLinks[focusedRow]!,
              showWhenUnlinked: false,
              // Position on the right border, centered vertically
              // Similar to row handle which uses Offset(-10, 5) for left side
              // For right side: colWidth positions at right edge, cellHeight/2 centers vertically
              // Add small offset (5) to match row handle's vertical positioning
              offset: Offset(colWidth - 10, cellHeight / 2 - 10),
              child: TableActionHandler(
                visible: true,
                node: widget.tableNode.node,
                editorState: widget.editorState,
                position: focusedRow,
                alignment: Alignment.centerRight, // Align to right, center vertically
                height: null,
                menuBuilder: widget.menuBuilder,
                dir: TableDirection.cell,
                cellFocusNotifier: widget.cellFocusNotifier,
              ),
            ),
          );
        },
      ),
    );

    overlay.insert(_cellHandlesOverlayEntry!);
  }

  void _cleanupListeners() {
    for (final entry in listeners.entries) {
      // Remove listener from stored node reference
      try {
        final node = _listenerNodes[entry.key];
        if (node != null) {
          node.removeListener(entry.value);
        }
      } catch (e) {
        // Node might have been disposed, ignore
      }
    }
    listeners.clear();
    _listenerNodes.clear();
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
        child: SizedBox(width: widget.tableNode.config.borderWidth),
      ),
    ]);

    // Use a Stack to allow the resize handle to be larger than the visible border
    // without affecting the layout of adjacent columns
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IntrinsicHeight(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
        // Left Helper Handle: Resizes the PREVIOUS column (if not the first column)
        // This extends the hitbox of the previous column's right border into this column.
        if (widget.colIdx > 0)
          Positioned(
            left: 0,
            top: 10,
            bottom: 0,
            width: Platform.isMacOS || Platform.isAndroid ? 12 : 5.0, // Extends 12px into this column
            child: TableColBorder(
              resizable: true,
              tableNode: widget.tableNode,
              editorState: widget.editorState,
              // Bind to the previous column index
              colIdx: widget.colIdx - 1,
              // Helper is transparent, purely for hit testing
              borderColor: Colors.transparent,
              borderHoverColor: Colors.transparent,
              hitboxWidth: Platform.isMacOS || Platform.isAndroid ? 12 : 5.0,
              hitboxAlignment: Alignment.centerLeft,
              activeColNotifier: widget.colResizeHoverNotifier,
            ),
          ),
        // Right Handle: Resizes THIS column
        // This is the main handle that also draws the visible border.
        Positioned(
          right: 0,
          top: 10,
          bottom: 0,
          width: Platform.isMacOS || Platform.isAndroid ? 12 : 5.0, // Extends 12px into this column
          child: TableColBorder(
            resizable: true,
            tableNode: widget.tableNode,
            editorState: widget.editorState,
            colIdx: widget.colIdx,
            borderColor: widget.tableStyle.borderColor,
            borderHoverColor: widget.tableStyle.borderHoverColor,
            hitboxWidth: Platform.isMacOS || Platform.isAndroid ? 12 : 5.0,
            hitboxAlignment: Alignment.centerRight,
            activeColNotifier: widget.colResizeHoverNotifier,
          ),
        ),
      ],
    );
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

      // Only set up listeners once per cell node
      final cellKey = '${node.id}_$i';
      if (!_initializedCellNodes.contains(cellKey)) {
        addListener(node, i);
        // Only add listener to first child if it exists
        if (node.children.isNotEmpty) {
          addListener(node.children.first, i);
        }
        _initializedCellNodes.add(cellKey);
      }

      // Use key to help Flutter identify which cells need rebuilding
      Widget cellWidget = RepaintBoundary(
        key: ValueKey('cell_${node.id}_${widget.colIdx}_$i'),
        child: widget.editorState.renderer.build(
          context,
          node,
        ),
      );

      // Wrap the cell with the providers
      cellWidget = MultiProvider(
        providers: [
          ChangeNotifierProvider<TableRowActionNotifier>.value(
            value: widget.rowActionNotifier,
          ),
          ChangeNotifierProvider<TableCellFocusNotifier>.value(
            value: widget.cellFocusNotifier,
          ),
        ],
        child: cellWidget,
      );

      // Wrap the cell with the row action notifier for hover detection
      // Wrap ALL cells with TableRowDragTarget so any cell can accept the drop
      cellWidget = TableRowDragTarget(
        tableNode: widget.tableNode.node,
        rowIdx: i,
        colIdx: widget.colIdx,
        editorState: widget.editorState,
        dragNotifier: widget.rowDragNotifier,
        cellFocusNotifier: widget.cellFocusNotifier,
        child: cellWidget,
      );

      // Add CompositedTransformTarget for the first column to anchor row handles
      if (widget.colIdx == 0) {
        _layerLinks.putIfAbsent(i, () => LayerLink());
        cellWidget = CompositedTransformTarget(
          link: _layerLinks[i]!,
          child: cellWidget,
        );
      }

      // Add CompositedTransformTarget for all cells to anchor cell handles on right border
      _cellLayerLinks.putIfAbsent(i, () => LayerLink());
      cellWidget = CompositedTransformTarget(
        link: _cellLayerLinks[i]!,
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

      // Add visual indicator line when cell is focused
      cellWidget = ListenableBuilder(
        listenable: widget.cellFocusNotifier,
        builder: (context, child) {
          final isCellFocused = widget.cellFocusNotifier.isCellFocused(i, widget.colIdx);

          if (!isCellFocused) return child!;

          return Stack(
            children: [
              child!,
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: widget.tableStyle.borderHoverColor,
                        width: 2,
                      ),
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
        child: Column(
          children: [
            cellBorder,
            ...cells,
          ],
        ),
      ),
    ];
  }

  void addListener(Node node, int row) {
    if (listeners.containsKey(node.id)) {
      return;
    }

    listeners[node.id] = () => updateRowHeightCallback(row);
    _listenerNodes[node.id] = node;
    node.addListener(listeners[node.id]!);
  }

  void updateRowHeightCallback(int row) {
    // Add to pending updates
    _pendingRowHeightUpdates.add(row);

    // Cancel existing timer
    _rowHeightUpdateTimer?.cancel();

    // Debounce the update to batch multiple rapid changes
    _rowHeightUpdateTimer = Timer(const Duration(milliseconds: 150), () {
      if (!mounted || _pendingRowHeightUpdates.isEmpty) {
        return;
      }

      // Process all pending row height updates in a single transaction
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        final rowsToUpdate = Set<int>.from(_pendingRowHeightUpdates);
        _pendingRowHeightUpdates.clear();

        // Filter out invalid rows
        final validRows = rowsToUpdate.where((r) => r < widget.tableNode.rowsLen).toSet();
        if (validRows.isEmpty) {
          return;
        }

        // Reset cached width when row height changes as it might affect column layout
        _cachedColWidth = null;

        // Batch update all affected rows in a single transaction
        final transaction = widget.editorState.transaction;
        for (final row in validRows) {
          widget.tableNode.updateRowHeight(
            row,
            editorState: widget.editorState,
            transaction: transaction,
          );
        }

        if (transaction.operations.isNotEmpty) {
          transaction.afterSelection = transaction.beforeSelection;
          widget.editorState.apply(transaction);
        }
      });
    });
  }
}
