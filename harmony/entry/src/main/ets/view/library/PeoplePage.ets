import { ImmichApiError, ImmichPerson, ImmichPeopleApi, TimelineQueryRaw } from 'network';
import { AssetImageLoader } from '../timeline/AssetImageLoader';
import { NavStackHolder } from './AssetBucketGridPage';
import { AssetGridParam } from './AssetGridPage';

/** One circular person avatar loaded from /people/{id}/thumbnail. */
@ComponentV2
struct PersonAvatar {
  @Param personId: string = '';
  @Local avatar: PixelMap | null = null;

  aboutToAppear(): void {
    const personId: string = this.personId;
    AssetImageLoader.loadPersonAvatar(personId).then((pm: PixelMap): void => {
      this.avatar = pm;
    }).catch((err: Error): void => {
      // placeholder circle stays
    });
  }

  build() {
    Stack() {
      if (this.avatar !== null) {
        Image(this.avatar)
          .objectFit(ImageFit.Cover)
          .width('100%')
          .height('100%')
      }
    }
    .width(72)
    .height(72)
    .borderRadius(36)
    .backgroundColor($r('app.color.immich_outline'))
    .clip(true)
  }
}

/**
 * "people" route: grid of recognized people with avatars; tapping a person
 * opens their photos via the generic assetGrid route.
 */
@ComponentV2
export struct PeoplePage {
  @Local people: ImmichPerson[] = [];
  @Local loading: boolean = true;
  @Local errorText: string = '';
  private stackHolder: NavStackHolder = new NavStackHolder();

  aboutToAppear(): void {
    this.loadPeople();
  }

  build() {
    NavDestination() {
      if (this.errorText.length > 0) {
        Column({ space: 12 }) {
          Text(this.errorText)
            .fontSize(14)
            .fontColor($r('app.color.immich_error'))
            .textAlign(TextAlign.Center)
            .padding({ left: 24, right: 24 })
          Button($r('app.string.common_retry'))
            .buttonStyle(ButtonStyleMode.NORMAL)
            .onClick(() => {
              this.loadPeople();
            })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.loading) {
        Column({ space: 12 }) {
          LoadingProgress()
            .width(36)
            .height(36)
            .color($r('app.color.immich_primary'))
          Text($r('app.string.timeline_loading'))
            .fontSize(14)
            .fontColor($r('app.color.immich_text_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.people.length === 0) {
        Column({ space: 12 }) {
          Text($r('app.string.people_empty'))
            .fontSize(14)
            .fontColor($r('app.color.immich_text_secondary'))
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .padding({ left: 40, right: 40 })
      } else {
        Grid() {
          ForEach(this.people, (person: ImmichPerson) => {
            GridItem() {
              Column({ space: 6 }) {
                PersonAvatar({ personId: person.id })
                Text(person.name.length > 0 ? person.name : this.unnamedLabel())
                  .fontSize(12)
                  .fontColor($r('app.color.immich_text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .constraintSize({ maxWidth: '90%' })
              }
              .justifyContent(FlexAlign.Center)
            }
            .onClick(() => {
              this.openPerson(person);
            })
          }, (person: ImmichPerson) => person.id)
        }
        .columnsTemplate('1fr 1fr 1fr 1fr')
        .columnsGap(4)
        .rowsGap(16)
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 8, right: 8, top: 16 })
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .title($r('app.string.people_title'))
    .backgroundColor($r('app.color.immich_bg'))
    .onReady((ctx: NavDestinationContext) => {
      this.stackHolder.stack = ctx.pathStack;
    })
  }

  private async loadPeople(): Promise<void> {
    this.loading = true;
    this.errorText = '';
    try {
      this.people = await ImmichPeopleApi.getPeople();
    } catch (err) {
      this.errorText = err instanceof ImmichApiError ? err.message : 'network error';
    }
    this.loading = false;
  }

  private openPerson(person: ImmichPerson): void {
    const title: string = person.name.length > 0 ? person.name : this.unnamedLabel();
    const queryRaw: TimelineQueryRaw = { personId: person.id };
    const param: AssetGridParam = { title: title, query: queryRaw };
    this.stackHolder.stack.pushPathByName('assetGrid', JSON.stringify(param), false);
  }

  private unnamedLabel(): string {
    return this.loadString('people_unnamed');
  }

  private loadString(name: string): string {
    const context: Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      return '';
    }
    return context.resourceManager.getStringByNameSync(name);
  }
}

/** Route-table builder for the "people" destination. */
@Builder
export function PeopleBuilder() {
  PeoplePage()
}
