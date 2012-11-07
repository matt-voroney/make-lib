, := ,

$$ := $$

define \n


endef
define \t
	
endef
space :=
space +=

#
# unpacks a record using ':' as a field delimiter into a list.
#
unpack = $(subst :,$(space),$(subst ::,:null:,$1))

#
# packs a list of values into a record using ':' as a field delimiter.
#
pack = $(subst null,,$(subst $(space),:,$(strip $1)))

#
# Extracts a packed field
#
define field
$(word $1,$(call unpack,$2))
endef

alphabet := a b c d e f g h i j k l m n o p q r s t u v w x y z
ALPHABET := A B C D E F G H I J K L M N O P Q R S T U V W X Y Z

#
# Translates each occurence of the symbols in $1 in the list of words in $3 
# with the corresponding symbol from $2
#
# $1 - the list of symbols to translate.
# $2 - the list of symbols to translate into.
# $3 - the list of words to translate.
#
define translate
$(if $1,$(call translate,$(call tail,$1),$(call tail,$2),$(subst $(word 1,$1),$(word 1,$2),$3)),$3)
endef

define uppercase
$(call translate,$(alphabet),$(ALPHABET),$1)
endef

define lowercase
$(call translate,$(ALPHABET),$(alphabet),$1)
endef

#
# Pads a list to the specified size with the specified value. If the list is
# already greater than or equal to the specified size, nothing is done.
#
# $1 - the size to pad the list to.
# $2 - the value to pad the list with.
# $3 - the list to pad.
#
define list_pad
$(if $(word $1,$3),$3,$(call list_pad,$1,$2,$(strip $3 $2)))
endef

#
# returns the tail of the list.
#
# $1 - a list
#
define tail
$(wordlist 2,$(words $(1)),$(1))
endef

#
# Generic list processing routine. Can be used to implement map and filter
# operations.
#
# $1 - the name of the operation to perform on each list element. The
#      operation is expected to accept an externally supplied argument ($2),
#      and the current list item. i.e $(call operation,arg,item) is executed
#      on each list item.
# $2 - an extra argument to supply to the operation defined by $1.
# $3 - the list of items to process.
#
# Return - the concatenation of the results of all of the applications of $1
#          to the list in $3
#
define list_items
$(if $(word 1,$3),$(strip $(call $1,$2,$(word 1,$3)) $(call list_items,$1,$2,$(call tail,$3))),)
endef

define list_rm
$(call list_items,without_string,$1,$2)
endef

define list_with
$(call list_items,with_string,$1,$2)
endef

#
# extracts the key at index $1 in map $2
#
define map_index
$(word $(call translate,key value,1 2,$2),$(subst :,$(space),$(word $1,$3)))
endef

#
# extracts the value corresponding to key $1 in map $2
# 0 or more items may be returned.
#
define map_value
$(subst $1:,,$(filter $1:%,$2))
endef

# TODO: does not work for multimaps.
#
# extracts the key corresponding to the value $1 in map $2
# 0 or more items may be returned.
#
define map_key
$(subst :$1,,$(filter %:$1,$2))
endef

define map_keys
$(foreach elt,$1,$(call field,1,$(elt)))
endef

define map_strip
$(foreach elt,$2,$(call pack,$(filter-out $(call field,$1,$(elt)),$(call unpack,$(elt)))))
endef

define map_values
$(call map_strip,1,$1)
endef

# TODO: is this useful for anything?
nop =

define with_string 
$(if $(findstring $1,$2),$2,)
endef

define without_string
$(if $(findstring $1,$2),,$2)
endef

#
# Adds the specified prefix to all fields in the map.
#
# $1 - the prefix to apply.
# $2 - the map to prefix the fields of.
#
define map_prefix
$(foreach elt,$2,$(call pack,$(addprefix $1,$(call unpack,$(elt)))))
endef

