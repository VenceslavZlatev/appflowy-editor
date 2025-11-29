import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

final textDecorationMobileToolbarItemV2 = MobileToolbarItem.withMenu(
  itemIconBuilder: (context, __, ___) => AFMobileIcon(
    afMobileIcons: AFMobileIcons.textDecoration,
    color: MobileToolbarTheme.of(context).iconColor,
  ),
  itemMenuBuilder: (_, editorState, service) {
    final selection = editorState.selection;
    if (selection == null) {
      return const SizedBox.shrink();
    }
    return _TextDecorationMenu(
      editorState,
      selection,
      service,
    );
  },
  displayMenuInline: true,
);

class _TextDecorationMenu extends StatefulWidget {
  const _TextDecorationMenu(
    this.editorState,
    this.selection,
    this.toolbarWidgetService,
  );

  final EditorState editorState;
  final Selection selection;
  final MobileToolbarWidgetService toolbarWidgetService;

  @override
  State<_TextDecorationMenu> createState() => _TextDecorationMenuState();
}

class _TextDecorationMenuState extends State<_TextDecorationMenu> {
  final textDecorations = [
    // BIUS
    TextDecorationUnit(
      icon: AFMobileIcons.bold,
      label: AppFlowyEditorL10n.current.bold,
      name: AppFlowyRichTextKeys.bold,
    ),
    TextDecorationUnit(
      icon: AFMobileIcons.italic,
      label: AppFlowyEditorL10n.current.italic,
      name: AppFlowyRichTextKeys.italic,
    ),
    TextDecorationUnit(
      icon: AFMobileIcons.underline,
      label: AppFlowyEditorL10n.current.underline,
      name: AppFlowyRichTextKeys.underline,
    ),
    TextDecorationUnit(
      icon: AFMobileIcons.strikethrough,
      label: AppFlowyEditorL10n.current.strikethrough,
      name: AppFlowyRichTextKeys.strikethrough,
    ),

    // Code
    TextDecorationUnit(
      icon: AFMobileIcons.code,
      label: AppFlowyEditorL10n.current.embedCode,
      name: AppFlowyRichTextKeys.code,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final style = MobileToolbarTheme.of(context);
    final selection = widget.selection;
    final nodes = widget.editorState.getNodesInSelection(selection);

    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      physics: const ClampingScrollPhysics(),
      itemCount: textDecorations.length,
      separatorBuilder: (_, __) => const SizedBox(width: 4),
      itemBuilder: (context, index) {
        final currentDecoration = textDecorations[index];
        final bool isInlineActive = widget.toolbarWidgetService.isInlineAttributeActive(currentDecoration.name);
        final bool isSelected;
        if (selection.isCollapsed) {
          final toggledValue = widget.editorState.toggledStyle[currentDecoration.name] == true;
          isSelected = toggledValue || isInlineActive;
        } else {
          isSelected = nodes.allSatisfyInSelection(selection, (delta) {
            return delta.everyAttributes(
              (attributes) => attributes[currentDecoration.name] == true,
            );
          });
        }

        return Container(
          decoration: isSelected
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(style.borderRadius),
                  border: Border.all(
                    color: style.itemHighlightColor,
                    width: style.buttonSelectedBorderWidth,
                  ),
                )
              : null,
          child: IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              setState(() {
                widget.editorState.toggleAttribute(
                  currentDecoration.name,
                  selectionExtraInfo: {
                    selectionExtraInfoDoNotAttachTextService: true,
                  },
                );
              });
              final nextState = !isSelected;
              if (selection.isCollapsed) {
                widget.toolbarWidgetService.setInlineAttributeActive(
                  currentDecoration.name,
                  nextState,
                );
              } else if (!nextState) {
                widget.toolbarWidgetService.setInlineAttributeActive(
                  currentDecoration.name,
                  false,
                );
              }
            },
            icon: AFMobileIcon(
              afMobileIcons: currentDecoration.icon,
              color: isSelected ? style.itemHighlightColor : style.iconColor,
            ),
          ),
        );
      },
    );
  }
}
