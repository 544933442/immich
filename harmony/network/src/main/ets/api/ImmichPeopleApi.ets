import { http } from '@kit.NetworkKit';
import { ImmichHttpClient } from '../ImmichHttpClient';
import { ImmichPerson, ImmichPersonRaw, PeopleResponseRaw } from '../model/ApiModels';

/** Server people (face recognition) APIs. */
export class ImmichPeopleApi {
  /** GET /people — all visible recognized people. */
  static async getPeople(): Promise<ImmichPerson[]> {
    const text: string = await ImmichHttpClient.requestJsonText(http.RequestMethod.GET, '/people');
    const raw: PeopleResponseRaw = JSON.parse(text) as PeopleResponseRaw;
    const entries: ImmichPersonRaw[] = raw.people ?? [];
    const people: ImmichPerson[] = [];
    for (const entry of entries) {
      const person: ImmichPerson = new ImmichPerson();
      person.id = entry.id;
      person.name = entry.name ?? '';
      people.push(person);
    }
    return people;
  }

  /** Download the face thumbnail of a person. */
  static async downloadPersonThumbnail(id: string): Promise<ArrayBuffer> {
    return ImmichHttpClient.requestBinary(http.RequestMethod.GET, `/people/${id}/thumbnail`);
  }
}
